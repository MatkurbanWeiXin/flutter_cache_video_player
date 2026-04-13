/// Linux 原生视频播放器插件，基于 GStreamer (playbin3) + FlPixelBufferTexture 实现。
/// Linux native video player plugin using GStreamer (playbin3) + FlPixelBufferTexture.

#include "include/flutter_cache_video_player/flutter_cache_video_player_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gst/gst.h>
#include <gst/video/video.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>

#include "flutter_cache_video_player_plugin_private.h"

// ══════════════════════════════════════════════════════════════════
// VideoTexture — FlPixelBufferTexture 子类，存储视频帧像素数据
// VideoTexture — FlPixelBufferTexture subclass storing video frame pixels
// ══════════════════════════════════════════════════════════════════

#define VIDEO_TEXTURE_TYPE (video_texture_get_type())
G_DECLARE_FINAL_TYPE(VideoTexture, video_texture, VIDEO, TEXTURE,
                     FlPixelBufferTexture)

struct _VideoTexture {
  FlPixelBufferTexture parent_instance;
  uint8_t* buffer;
  uint32_t width;
  uint32_t height;
  GMutex mutex;
};

G_DEFINE_TYPE(VideoTexture, video_texture, fl_pixel_buffer_texture_get_type())

static gboolean video_texture_copy_pixels_cb(FlPixelBufferTexture* tex,
                                              const uint8_t** out_buffer,
                                              uint32_t* width,
                                              uint32_t* height,
                                              GError** error) {
  VideoTexture* self = VIDEO_TEXTURE(tex);
  g_mutex_lock(&self->mutex);
  *out_buffer = self->buffer;
  *width = self->width;
  *height = self->height;
  g_mutex_unlock(&self->mutex);
  return self->buffer != nullptr;
}

static void video_texture_dispose(GObject* obj) {
  VideoTexture* self = VIDEO_TEXTURE(obj);
  g_mutex_lock(&self->mutex);
  g_free(self->buffer);
  self->buffer = nullptr;
  g_mutex_unlock(&self->mutex);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(video_texture_parent_class)->dispose(obj);
}

static void video_texture_class_init(VideoTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = video_texture_dispose;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      video_texture_copy_pixels_cb;
}

static void video_texture_init(VideoTexture* self) {
  g_mutex_init(&self->mutex);
  self->buffer = nullptr;
  self->width = 0;
  self->height = 0;
}

static VideoTexture* video_texture_new() {
  return VIDEO_TEXTURE(g_object_new(VIDEO_TEXTURE_TYPE, nullptr));
}

// ══════════════════════════════════════════════════════════════════
// Plugin 主结构 / Plugin main struct
// ══════════════════════════════════════════════════════════════════

#define FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN(obj)                     \
  (G_TYPE_CHECK_INSTANCE_CAST(                                     \
      (obj), flutter_cache_video_player_plugin_get_type(),         \
      FlutterCacheVideoPlayerPlugin))

struct _FlutterCacheVideoPlayerPlugin {
  GObject parent_instance;
  FlTextureRegistrar* texture_registrar;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  VideoTexture* texture;
  int64_t texture_id;
  GstElement* pipeline;
  guint position_timer_id;
};

G_DEFINE_TYPE(FlutterCacheVideoPlayerPlugin,
              flutter_cache_video_player_plugin, g_object_get_type())

// ── 事件发送 / Event sending ──

typedef struct {
  FlEventChannel* channel;
  gchar* name;
  FlValue* value;
} EventPayload;

static gboolean send_event_idle_cb(gpointer data) {
  EventPayload* p = static_cast<EventPayload*>(data);
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "event", fl_value_new_string(p->name));
  fl_value_set_string(map, "value", p->value);
  fl_event_channel_send(p->channel, map, nullptr, nullptr);
  g_free(p->name);
  fl_value_unref(p->value);
  g_free(p);
  return G_SOURCE_REMOVE;
}

static void send_event(FlutterCacheVideoPlayerPlugin* self,
                        const gchar* name, FlValue* value) {
  if (!self->event_channel) return;
  EventPayload* p = g_new(EventPayload, 1);
  p->channel = self->event_channel;
  p->name = g_strdup(name);
  p->value = fl_value_ref(value);
  g_idle_add(send_event_idle_cb, p);
}

static void send_event_int(FlutterCacheVideoPlayerPlugin* self,
                            const gchar* name, int64_t val) {
  g_autoptr(FlValue) v = fl_value_new_int(val);
  send_event(self, name, v);
}

static void send_event_bool(FlutterCacheVideoPlayerPlugin* self,
                             const gchar* name, gboolean val) {
  g_autoptr(FlValue) v = fl_value_new_bool(val);
  send_event(self, name, v);
}

static void send_event_null(FlutterCacheVideoPlayerPlugin* self,
                             const gchar* name) {
  g_autoptr(FlValue) v = fl_value_new_null();
  send_event(self, name, v);
}

static void send_event_str(FlutterCacheVideoPlayerPlugin* self,
                            const gchar* name, const gchar* val) {
  g_autoptr(FlValue) v = fl_value_new_string(val);
  send_event(self, name, v);
}

// ── GStreamer 回调 / GStreamer callbacks ──

static GstFlowReturn on_new_sample(GstElement* sink, gpointer user_data) {
  auto* self = static_cast<FlutterCacheVideoPlayerPlugin*>(user_data);

  GstSample* sample = nullptr;
  g_signal_emit_by_name(sink, "pull-sample", &sample);
  if (!sample) return GST_FLOW_ERROR;

  GstBuffer* buffer = gst_sample_get_buffer(sample);
  GstCaps* caps = gst_sample_get_caps(sample);
  GstVideoInfo info;
  gst_video_info_from_caps(&info, caps);

  GstMapInfo map;
  if (!gst_buffer_map(buffer, &map, GST_MAP_READ)) {
    gst_sample_unref(sample);
    return GST_FLOW_ERROR;
  }

  uint32_t w = GST_VIDEO_INFO_WIDTH(&info);
  uint32_t h = GST_VIDEO_INFO_HEIGHT(&info);

  g_mutex_lock(&self->texture->mutex);
  if (self->texture->width != w || self->texture->height != h) {
    g_free(self->texture->buffer);
    self->texture->buffer =
        static_cast<uint8_t*>(g_malloc(static_cast<size_t>(w) * h * 4));
    self->texture->width = w;
    self->texture->height = h;
  }

  uint32_t stride = GST_VIDEO_INFO_PLANE_STRIDE(&info, 0);
  if (stride == w * 4) {
    memcpy(self->texture->buffer, map.data,
           static_cast<size_t>(w) * h * 4);
  } else {
    for (uint32_t row = 0; row < h; row++) {
      memcpy(self->texture->buffer + row * w * 4,
             map.data + row * stride, w * 4);
    }
  }
  g_mutex_unlock(&self->texture->mutex);

  gst_buffer_unmap(buffer, &map);
  gst_sample_unref(sample);

  fl_texture_registrar_mark_texture_frame_available(
      self->texture_registrar, FL_TEXTURE(self->texture));

  return GST_FLOW_OK;
}

static gboolean on_bus_message(GstBus* bus, GstMessage* msg,
                                gpointer user_data) {
  auto* self = static_cast<FlutterCacheVideoPlayerPlugin*>(user_data);

  switch (GST_MESSAGE_TYPE(msg)) {
    case GST_MESSAGE_EOS:
      send_event_null(self, "completed");
      break;
    case GST_MESSAGE_ERROR: {
      GError* error = nullptr;
      gst_message_parse_error(msg, &error, nullptr);
      send_event_str(self, "error", error->message);
      g_error_free(error);
      break;
    }
    case GST_MESSAGE_DURATION_CHANGED: {
      gint64 dur = 0;
      if (gst_element_query_duration(self->pipeline, GST_FORMAT_TIME, &dur)) {
        send_event_int(self, "duration",
                       static_cast<int64_t>(dur / GST_MSECOND));
      }
      break;
    }
    case GST_MESSAGE_STATE_CHANGED: {
      if (GST_MESSAGE_SRC(msg) == GST_OBJECT(self->pipeline)) {
        GstState old_st, new_st;
        gst_message_parse_state_changed(msg, &old_st, &new_st, nullptr);
        if (new_st == GST_STATE_PLAYING) {
          send_event_bool(self, "playing", TRUE);
          send_event_bool(self, "buffering", FALSE);
        } else if (new_st == GST_STATE_PAUSED &&
                   old_st == GST_STATE_PLAYING) {
          send_event_bool(self, "playing", FALSE);
        }
      }
      break;
    }
    case GST_MESSAGE_BUFFERING: {
      gint pct = 0;
      gst_message_parse_buffering(msg, &pct);
      send_event_bool(self, "buffering", pct < 100);
      break;
    }
    default:
      break;
  }
  return TRUE;
}

static gboolean position_timer_cb(gpointer user_data) {
  auto* self = static_cast<FlutterCacheVideoPlayerPlugin*>(user_data);
  if (!self->pipeline) return TRUE;

  gint64 pos = 0;
  if (gst_element_query_position(self->pipeline, GST_FORMAT_TIME, &pos)) {
    send_event_int(self, "position",
                   static_cast<int64_t>(pos / GST_MSECOND));
  }
  return TRUE;
}

// ── 播放器控制 / Player control ──

static void cleanup_pipeline(FlutterCacheVideoPlayerPlugin* self) {
  if (self->position_timer_id) {
    g_source_remove(self->position_timer_id);
    self->position_timer_id = 0;
  }
  if (self->pipeline) {
    gst_element_set_state(self->pipeline, GST_STATE_NULL);
    gst_object_unref(self->pipeline);
    self->pipeline = nullptr;
  }
}

static int64_t player_create(FlutterCacheVideoPlayerPlugin* self) {
  self->texture = video_texture_new();
  fl_texture_registrar_register_texture(self->texture_registrar,
                                         FL_TEXTURE(self->texture));
  self->texture_id =
      fl_texture_get_id(FL_TEXTURE(self->texture));
  return self->texture_id;
}

static void player_open(FlutterCacheVideoPlayerPlugin* self,
                         const gchar* url) {
  cleanup_pipeline(self);

  self->pipeline = gst_element_factory_make("playbin3", "playbin");
  if (!self->pipeline) {
    self->pipeline = gst_element_factory_make("playbin", "playbin");
  }
  if (!self->pipeline) {
    send_event_str(self, "error", "Failed to create GStreamer pipeline");
    return;
  }

  g_object_set(self->pipeline, "uri", url, nullptr);

  // 创建 appsink 用于视频帧提取 / Create appsink for video frame extraction
  GstElement* sink = gst_element_factory_make("appsink", "videosink");
  GstCaps* caps = gst_caps_new_simple("video/x-raw", "format",
                                       G_TYPE_STRING, "BGRA", nullptr);
  g_object_set(sink, "caps", caps, "emit-signals", TRUE, "sync", TRUE,
               "max-buffers", 1, "drop", TRUE, nullptr);
  gst_caps_unref(caps);
  g_signal_connect(sink, "new-sample", G_CALLBACK(on_new_sample), self);
  g_object_set(self->pipeline, "video-sink", sink, nullptr);

  // 总线消息监听 / Bus message watch
  GstBus* bus = gst_element_get_bus(self->pipeline);
  gst_bus_add_watch(bus, on_bus_message, self);
  gst_object_unref(bus);

  gst_element_set_state(self->pipeline, GST_STATE_PLAYING);

  // 位置更新定时器 200ms / Position update timer 200ms
  self->position_timer_id =
      g_timeout_add(200, position_timer_cb, self);

  send_event_bool(self, "buffering", TRUE);
}

static void player_play(FlutterCacheVideoPlayerPlugin* self) {
  if (self->pipeline)
    gst_element_set_state(self->pipeline, GST_STATE_PLAYING);
}

static void player_pause(FlutterCacheVideoPlayerPlugin* self) {
  if (self->pipeline)
    gst_element_set_state(self->pipeline, GST_STATE_PAUSED);
}

static void player_seek(FlutterCacheVideoPlayerPlugin* self, int64_t ms) {
  if (!self->pipeline) return;
  gst_element_seek_simple(self->pipeline, GST_FORMAT_TIME,
                           static_cast<GstSeekFlags>(
                               GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_KEY_UNIT),
                           ms * GST_MSECOND);
}

static void player_set_volume(FlutterCacheVideoPlayerPlugin* self,
                               double vol) {
  if (self->pipeline) g_object_set(self->pipeline, "volume", vol, nullptr);
}

static void player_set_speed(FlutterCacheVideoPlayerPlugin* self,
                              double speed) {
  if (!self->pipeline) return;
  gint64 pos = 0;
  gst_element_query_position(self->pipeline, GST_FORMAT_TIME, &pos);
  if (speed > 0) {
    gst_element_seek(self->pipeline, speed, GST_FORMAT_TIME,
                     static_cast<GstSeekFlags>(
                         GST_SEEK_FLAG_FLUSH | GST_SEEK_FLAG_ACCURATE),
                     GST_SEEK_TYPE_SET, pos,
                     GST_SEEK_TYPE_NONE, GST_CLOCK_TIME_NONE);
  }
}

static void player_dispose(FlutterCacheVideoPlayerPlugin* self) {
  cleanup_pipeline(self);
  if (self->texture) {
    fl_texture_registrar_unregister_texture(self->texture_registrar,
                                             FL_TEXTURE(self->texture));
    g_object_unref(self->texture);
    self->texture = nullptr;
    self->texture_id = -1;
  }
}

// ── MethodChannel 处理 / MethodChannel handler ──

static void handle_method_call(FlutterCacheVideoPlayerPlugin* self,
                                FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "create") == 0) {
    int64_t id = player_create(self);
    g_autoptr(FlValue) result = fl_value_new_int(id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));

  } else if (strcmp(method, "open") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* url_val = fl_value_lookup_string(args, "url");
    if (url_val) {
      player_open(self, fl_value_get_string(url_val));
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "play") == 0) {
    player_play(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "pause") == 0) {
    player_pause(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "seek") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* pos = fl_value_lookup_string(args, "position");
    if (pos) player_seek(self, fl_value_get_int(pos));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setVolume") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* vol = fl_value_lookup_string(args, "volume");
    if (vol) player_set_volume(self, fl_value_get_float(vol));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "setSpeed") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* spd = fl_value_lookup_string(args, "speed");
    if (spd) player_set_speed(self, fl_value_get_float(spd));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "dispose") == 0) {
    player_dispose(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));

  } else if (strcmp(method, "getPlatformVersion") == 0) {
    response = get_platform_version();

  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* get_platform_version() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar* version =
      g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

// ── GObject 生命周期 / GObject lifecycle ──

static void flutter_cache_video_player_plugin_dispose(GObject* object) {
  auto* self = FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN(object);
  player_dispose(self);
  g_clear_object(&self->method_channel);
  g_clear_object(&self->event_channel);
  G_OBJECT_CLASS(flutter_cache_video_player_plugin_parent_class)
      ->dispose(object);
}

static void flutter_cache_video_player_plugin_class_init(
    FlutterCacheVideoPlayerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose =
      flutter_cache_video_player_plugin_dispose;
}

static void flutter_cache_video_player_plugin_init(
    FlutterCacheVideoPlayerPlugin* self) {
  self->texture = nullptr;
  self->texture_id = -1;
  self->pipeline = nullptr;
  self->position_timer_id = 0;
}

static void method_call_cb(FlMethodChannel* channel,
                            FlMethodCall* method_call,
                            gpointer user_data) {
  auto* plugin = FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN(user_data);
  handle_method_call(plugin, method_call);
}

// ── 插件注册 / Plugin registration ──

void flutter_cache_video_player_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  gst_init(nullptr, nullptr);

  FlutterCacheVideoPlayerPlugin* plugin =
      FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN(
          g_object_new(flutter_cache_video_player_plugin_get_type(), nullptr));

  plugin->texture_registrar =
      fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  // MethodChannel
  plugin->method_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_cache_video_player/player", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->method_channel, method_call_cb,
      g_object_ref(plugin), g_object_unref);

  // EventChannel
  plugin->event_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_cache_video_player/player/events", FL_METHOD_CODEC(codec));

  g_object_unref(plugin);
}
