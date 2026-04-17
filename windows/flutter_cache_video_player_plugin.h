#ifndef FLUTTER_PLUGIN_FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN_H_

// Windows video player plugin — libmpv backend (software rendering).

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>
#include <windows.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "mpv_player.h"

namespace flutter_cache_video_player {

class FlutterCacheVideoPlayerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit FlutterCacheVideoPlayerPlugin(flutter::PluginRegistrarWindows* registrar);
  ~FlutterCacheVideoPlayerPlugin() override;

  FlutterCacheVideoPlayerPlugin(const FlutterCacheVideoPlayerPlugin&) = delete;
  FlutterCacheVideoPlayerPlugin& operator=(const FlutterCacheVideoPlayerPlugin&) = delete;

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

 private:
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void EnsurePlayer();
  int64_t CreateTextureIfNeeded();
  void DisposePlayer();
  void SendEvent(const std::string& name, flutter::EncodableValue value);

  flutter::PluginRegistrarWindows* registrar_;
  flutter::TextureRegistrar* texture_registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;

  std::unique_ptr<MpvPlayer> player_;
  std::unique_ptr<flutter::TextureVariant> texture_variant_;
  int64_t texture_id_ = -1;
  FlutterDesktopPixelBuffer pixel_buffer_{};
  std::vector<uint8_t> pixel_buffer_data_;
  std::mutex pixel_mutex_;

  HWND message_window_ = nullptr;
  std::atomic<bool> drain_posted_{false};
  std::atomic<bool> render_posted_{false};

  static LRESULT CALLBACK MessageProc(HWND hwnd, UINT msg, WPARAM w, LPARAM l);
  static constexpr UINT kMsgDrain = WM_USER + 1;
  static constexpr UINT kMsgRender = WM_USER + 2;
};

}  // namespace flutter_cache_video_player

#endif  // FLUTTER_PLUGIN_FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN_H_
