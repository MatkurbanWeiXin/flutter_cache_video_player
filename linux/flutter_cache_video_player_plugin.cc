// Linux plugin implementation — libmpv + FlPixelBufferTexture (software rendering).

#include "include/flutter_cache_video_player/flutter_cache_video_player_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/stat.h>
#include <sys/utsname.h>

#include <cstring>
#include <memory>
#include <string>

#include "flutter_cache_video_player_plugin_private.h"
#include "mpv_player.h"

using flutter_cache_video_player::CoverFrame;
using flutter_cache_video_player::MpvPlayer;

#define VIDEO_TEXTURE_TYPE (video_texture_get_type())
G_DECLARE_FINAL_TYPE(VideoTexture, video_texture, VIDEO, TEXTURE, FlPixelBufferTexture)

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
                                             uint32_t* width, uint32_t* height,
                                             GError** /*error*/) {
  VideoTexture* self = VIDEO_TEXTURE(tex);
  g_mutex_lock(&self->mutex);
  *out_buffer = self->buffer;
  *width = self->width;
  *height = self->height;
  gboolean ok = self->buffer != nullptr;
  g_mutex_unlock(&self->mutex);
  return ok;
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
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = video_texture_copy_pixels_cb;
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

static void video_texture_write(VideoTexture* tex, const uint8_t* src,
                                uint32_t w, uint32_t h) {
  g_mutex_lock(&tex->mutex);
  if (tex->width != w || tex->height != h) {
    g_free(tex->buffer);
    tex->buffer = static_cast<uint8_t*>(g_malloc(static_cast<size_t>(w) * h * 4));
    tex->width = w;
    tex->height = h;
  }
  std::memcpy(tex->buffer, src, static_cast<size_t>(w) * h * 4);
  g_mutex_unlock(&tex->mutex);
}

#define FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), flutter_cache_video_player_plugin_get_type(), FlutterCacheVideoPlayerPlugin))

struct _FlutterCacheVideoPlayerPlugin {
  GObject parent_instance;
  FlTextureRegistrar* texture_registrar;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  VideoTexture* texture;
  int64_t texture_id;
  MpvPlayer* player;
  guint drain_source_id;
  guint render_source_id;
};

G_DEFINE_TYPE(FlutterCacheVideoPlayerPlugin, flutter_cache_video_player_plugin, g_object_get_type())

static void send_event(FlutterCacheVideoPlayerPlugin* self, const gchar* name, FlValue* value) {
  if (!self->event_channel) { if (value) fl_value_unref(value); return; }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "event", fl_value_new_string(name));
  fl_value_set_string_take(map, "value", value);
  fl_event_channel_send(self->event_channel, map, nullptr, nullptr);
}
static void send_event_int(FlutterCacheVideoPlayerPlugin* s, const gchar* n, int64_t v) { send_event(s, n, fl_value_new_int(v)); }
static void send_event_bool(FlutterCacheVideoPlayerPlugin* s, const gchar* n, gboolean v) { send_event(s, n, fl_value_new_bool(v)); }
static void send_event_null(FlutterCacheVideoPlayerPlugin* s, const gchar* n) { send_event(s, n, fl_value_new_null()); }
static void send_event_str(FlutterCacheVideoPlayerPlugin* s, const gchar* n, const gchar* v) { send_event(s, n, fl_value_new_string(v)); }

static gboolean drain_events_cb(gpointer user_data) {
  auto* self = static_cast<FlutterCacheVideoPlayerPlugin*>(user_data);
  self->drain_source_id = 0;
  if (self->player) self->player->DrainEvents();
  return G_SOURCE_REMOVE;
}

static gboolean render_cb(gpointer user_data) {
  auto* self = static_cast<FlutterCacheVideoPlayerPlugin*>(user_data);
  self->render_source_id = 0;
  if (self->player && self->player->Render()) {
    if (self->texture)
      fl_texture_registrar_mark_texture_frame_available(self->texture_registrar, FL_TEXTURE(self->texture));
  }
  return G_SOURCE_REMOVE;
}

static void ensure_player(FlutterCacheVideoPlayerPlugin* self) {
  if (self->player) return;
  auto* player = new MpvPlayer();
  std::string err;
  if (!player->Initialize(&err)) {
    delete player;
    send_event_str(self, "error", ("mpv init failed: " + err).c_str());
    return;
  }
  player->SetWakeupHandler([self]() {
    if (!self->drain_source_id) self->drain_source_id = g_idle_add(drain_events_cb, self);
  });
  player->SetUpdateHandler([self]() {
    if (!self->render_source_id) self->render_source_id = g_idle_add(render_cb, self);
  });
  player->SetOnPosition([self](int64_t ms) { send_event_int(self, "position", ms); });
  player->SetOnDuration([self](int64_t ms) { send_event_int(self, "duration", ms); });
  player->SetOnPlaying([self](bool p) { send_event_bool(self, "playing", p); });
  player->SetOnBuffering([self](bool b) { send_event_bool(self, "buffering", b); });
  player->SetOnCompleted([self]() { send_event_null(self, "completed"); });
  player->SetOnError([self](const std::string& m) { send_event_str(self, "error", m.c_str()); });
  player->SetOnFrame([self](const uint8_t* rgba, uint32_t w, uint32_t h) {
    if (self->texture) video_texture_write(self->texture, rgba, w, h);
  });
  player->SetOnVideoSize([self](int64_t w, int64_t h) {
    if (w <= 0 || h <= 0) return;
    FlValue* map = fl_value_new_map();
    fl_value_set_string_take(map, "width", fl_value_new_int(w));
    fl_value_set_string_take(map, "height", fl_value_new_int(h));
    send_event(self, "videoSize", map);
  });
  self->player = player;
}

static int64_t player_create(FlutterCacheVideoPlayerPlugin* self) {
  ensure_player(self);
  if (!self->texture) {
    self->texture = video_texture_new();
    fl_texture_registrar_register_texture(self->texture_registrar, FL_TEXTURE(self->texture));
    self->texture_id = fl_texture_get_id(FL_TEXTURE(self->texture));
  }
  return self->texture_id;
}

static void player_dispose(FlutterCacheVideoPlayerPlugin* self) {
  if (self->drain_source_id) { g_source_remove(self->drain_source_id); self->drain_source_id = 0; }
  if (self->render_source_id) { g_source_remove(self->render_source_id); self->render_source_id = 0; }
  if (self->player) { delete self->player; self->player = nullptr; }
  if (self->texture) {
    fl_texture_registrar_unregister_texture(self->texture_registrar, FL_TEXTURE(self->texture));
    g_object_unref(self->texture);
    self->texture = nullptr;
    self->texture_id = -1;
  }
}

static gchar* default_cover_dir() {
  const gchar* tmp = g_get_tmp_dir();
  gchar* dir = g_build_filename(tmp, "flutter_cache_video_player", "covers", nullptr);
  g_mkdir_with_parents(dir, 0700);
  return dir;
}

static void handle_method_call(FlutterCacheVideoPlayerPlugin* self, FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "create") == 0) {
    int64_t id = player_create(self);
    g_autoptr(FlValue) result = fl_value_new_int(id);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "open") == 0) {
    ensure_player(self);
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* url_val = args ? fl_value_lookup_string(args, "url") : nullptr;
    if (url_val && self->player) {
      self->player->Open(fl_value_get_string(url_val));
      send_event_bool(self, "buffering", TRUE);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "play") == 0) {
    if (self->player) self->player->Play();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "pause") == 0) {
    if (self->player) self->player->Pause();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "seek") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* pos = args ? fl_value_lookup_string(args, "position") : nullptr;
    if (pos && self->player) self->player->Seek(fl_value_get_int(pos));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setVolume") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* vol = args ? fl_value_lookup_string(args, "volume") : nullptr;
    if (vol && self->player) self->player->SetVolume(fl_value_get_float(vol));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "setSpeed") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* spd = args ? fl_value_lookup_string(args, "speed") : nullptr;
    if (spd && self->player) self->player->SetSpeed(fl_value_get_float(spd));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "dispose") == 0) {
    player_dispose(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (strcmp(method, "takeSnapshot") == 0) {
    if (!self->player) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new("NO_PLAYER", "Player not initialized", nullptr));
    } else {
      std::vector<uint8_t> bytes;
      std::string err;
      if (self->player->TakeSnapshot(&bytes, &err)) {
        g_autoptr(FlValue) data = fl_value_new_uint8_list(bytes.data(), bytes.size());
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(data));
      } else {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new("SNAPSHOT_FAIL", err.c_str(), nullptr));
      }
    }
  } else if (strcmp(method, "extractCovers") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* url = "";
    int count = 5, candidates = 15;
    double min_brightness = 0.08;
    std::string output_dir;
    if (args) {
      FlValue* v_url = fl_value_lookup_string(args, "url");
      FlValue* v_count = fl_value_lookup_string(args, "count");
      FlValue* v_cand = fl_value_lookup_string(args, "candidates");
      FlValue* v_minb = fl_value_lookup_string(args, "minBrightness");
      FlValue* v_dir = fl_value_lookup_string(args, "outputDir");
      if (v_url) url = fl_value_get_string(v_url);
      if (v_count) count = static_cast<int>(fl_value_get_int(v_count));
      if (v_cand) candidates = static_cast<int>(fl_value_get_int(v_cand));
      if (v_minb) min_brightness = fl_value_get_float(v_minb);
      if (v_dir && fl_value_get_length(v_dir) > 0) output_dir = fl_value_get_string(v_dir);
    }
    if (output_dir.empty()) { g_autofree gchar* d = default_cover_dir(); output_dir = d; }
    else g_mkdir_with_parents(output_dir.c_str(), 0700);

    auto frames = MpvPlayer::ExtractCovers(url, count, candidates, min_brightness, output_dir);
    g_autoptr(FlValue) list = fl_value_new_list();
    for (const auto& f : frames) {
      g_autoptr(FlValue) m = fl_value_new_map();
      fl_value_set_string_take(m, "path", fl_value_new_string(f.path.c_str()));
      fl_value_set_string_take(m, "positionMs", fl_value_new_int(f.position_ms));
      fl_value_set_string_take(m, "brightness", fl_value_new_float(f.brightness));
      fl_value_append(list, m);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
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
  g_autofree gchar* version = g_strdup_printf("Linux %s", uname_data.version);
  g_autoptr(FlValue) result = fl_value_new_string(version);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static void flutter_cache_video_player_plugin_dispose(GObject* object) {
  auto* self = FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN(object);
  player_dispose(self);
  g_clear_object(&self->method_channel);
  g_clear_object(&self->event_channel);
  G_OBJECT_CLASS(flutter_cache_video_player_plugin_parent_class)->dispose(object);
}

static void flutter_cache_video_player_plugin_class_init(FlutterCacheVideoPlayerPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = flutter_cache_video_player_plugin_dispose;
}

static void flutter_cache_video_player_plugin_init(FlutterCacheVideoPlayerPlugin* self) {
  self->texture = nullptr;
  self->texture_id = -1;
  self->player = nullptr;
  self->drain_source_id = 0;
  self->render_source_id = 0;
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* method_call, gpointer user_data) {
  handle_method_call(FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN(user_data), method_call);
}

static FlMethodErrorResponse* event_channel_listen_cb(FlEventChannel*, FlValue*, gpointer) { return nullptr; }
static FlMethodErrorResponse* event_channel_cancel_cb(FlEventChannel*, FlValue*, gpointer) { return nullptr; }

void flutter_cache_video_player_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  FlutterCacheVideoPlayerPlugin* plugin = FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN(
      g_object_new(flutter_cache_video_player_plugin_get_type(), nullptr));

  plugin->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  plugin->method_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_cache_video_player/player", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(plugin->method_channel, method_call_cb,
                                            g_object_ref(plugin), g_object_unref);

  plugin->event_channel = fl_event_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutter_cache_video_player/player/events", FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->event_channel, event_channel_listen_cb,
                                       event_channel_cancel_cb, plugin, nullptr);

  ensure_player(plugin);
  g_object_unref(plugin);
}
