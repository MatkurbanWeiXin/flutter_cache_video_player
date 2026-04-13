#ifndef FLUTTER_PLUGIN_FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN_H_
#define FLUTTER_PLUGIN_FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN_H_

/// Windows 视频播放器插件，基于 Media Foundation + D3D11 实现原生视频播放。
/// Windows video player plugin using Media Foundation + D3D11 for native video playback.

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>

#include <d3d11.h>
#include <mfapi.h>
#include <mfmediaengine.h>
#include <wrl/client.h>

#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace flutter_cache_video_player {

using Microsoft::WRL::ComPtr;

/// IMFMediaEngineNotify 回调实现，将媒体引擎事件转发给回调函数。
/// IMFMediaEngineNotify callback forwarding media engine events to a callback.
class MediaEngineNotify : public IMFMediaEngineNotify {
 public:
  using Callback = std::function<void(DWORD, DWORD_PTR, DWORD)>;
  explicit MediaEngineNotify(Callback cb) : callback_(std::move(cb)) {}

  ULONG STDMETHODCALLTYPE AddRef() override {
    return InterlockedIncrement(&ref_);
  }
  ULONG STDMETHODCALLTYPE Release() override {
    ULONG c = InterlockedDecrement(&ref_);
    if (c == 0) delete this;
    return c;
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID riid,
                                            void** ppv) override {
    if (riid == __uuidof(IUnknown) ||
        riid == __uuidof(IMFMediaEngineNotify)) {
      *ppv = static_cast<IMFMediaEngineNotify*>(this);
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  HRESULT STDMETHODCALLTYPE EventNotify(DWORD event, DWORD_PTR p1,
                                         DWORD p2) override {
    if (callback_) callback_(event, p1, p2);
    return S_OK;
  }

 private:
  long ref_ = 1;
  Callback callback_;
};

/// 原生视频播放器，使用 IMFMediaEngine 进行播放，D3D11 提取帧，PixelBufferTexture 渲染到 Flutter。
/// Native video player using IMFMediaEngine for playback, D3D11 for frame extraction,
/// and PixelBufferTexture for rendering to Flutter.
class NativeVideoPlayer {
 public:
  explicit NativeVideoPlayer(flutter::TextureRegistrar* registrar);
  ~NativeVideoPlayer();

  int64_t Create();
  void Open(const std::string& url);
  void Play();
  void Pause();
  void Seek(int64_t position_ms);
  void SetVolume(double volume);
  void SetSpeed(double speed);
  void Dispose();

  void SetEventSink(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink);

 private:
  bool InitD3D();
  bool InitMediaEngine();
  bool EnsureRenderTarget(UINT w, UINT h);
  void OnMediaEvent(DWORD event, DWORD_PTR p1, DWORD p2);
  void UpdateFrame();
  void StartFrameTimer();
  void StopFrameTimer();
  static void CALLBACK OnTimer(PVOID ctx, BOOLEAN fired);
  void SendEvent(const std::string& name, const flutter::EncodableValue& val);
  void Cleanup();

  flutter::TextureRegistrar* texture_registrar_;
  int64_t texture_id_ = -1;
  std::unique_ptr<flutter::PixelBufferTexture> pixel_texture_;

  ComPtr<ID3D11Device> d3d_device_;
  ComPtr<ID3D11DeviceContext> d3d_context_;
  ComPtr<IMFDXGIDeviceManager> dxgi_manager_;
  ComPtr<IMFMediaEngine> media_engine_;
  ComPtr<ID3D11Texture2D> render_tex_;
  ComPtr<ID3D11Texture2D> staging_tex_;

  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::mutex sink_mutex_;

  std::vector<uint8_t> pixel_data_;
  FlutterDesktopPixelBuffer pixel_buf_{};
  std::mutex buf_mutex_;

  HANDLE timer_handle_ = nullptr;
  UINT video_w_ = 0;
  UINT video_h_ = 0;
  UINT reset_token_ = 0;
  int frame_count_ = 0;
};

/// 插件主类，注册 MethodChannel 和 EventChannel，代理 NativeVideoPlayer 处理调用。
/// Plugin main class registering MethodChannel/EventChannel and delegating to NativeVideoPlayer.
class FlutterCacheVideoPlayerPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  FlutterCacheVideoPlayerPlugin(flutter::TextureRegistrar* tex_registrar,
                                 flutter::BinaryMessenger* messenger);
  virtual ~FlutterCacheVideoPlayerPlugin();

  FlutterCacheVideoPlayerPlugin(const FlutterCacheVideoPlayerPlugin&) = delete;
  FlutterCacheVideoPlayerPlugin& operator=(
      const FlutterCacheVideoPlayerPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::unique_ptr<NativeVideoPlayer> player_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      method_channel_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      event_channel_;
};

}  // namespace flutter_cache_video_player

#endif  // FLUTTER_PLUGIN_FLUTTER_CACHE_VIDEO_PLAYER_PLUGIN_H_
