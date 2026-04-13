/// Windows 原生视频播放器实现，使用 Media Foundation (IMFMediaEngine) + D3D11。
/// Windows native video player implementation using Media Foundation (IMFMediaEngine) + D3D11.

#include "flutter_cache_video_player_plugin.h"

#include <VersionHelpers.h>
#include <windows.h>

#include <sstream>
#include <string>

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "mfuuid.lib")
#pragma comment(lib, "d3d11.lib")

namespace flutter_cache_video_player {

// ── Helper: UTF-8 → wide string ──

static std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
  std::wstring w(n - 1, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
  return w;
}

// ── Helper: Get string arg from method call ──

static std::string GetStringArg(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const std::string& key) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) return "";
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return "";
  const auto* val = std::get_if<std::string>(&it->second);
  return val ? *val : "";
}

static double GetDoubleArg(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const std::string& key) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) return 0.0;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return 0.0;
  const auto* val = std::get_if<double>(&it->second);
  return val ? *val : 0.0;
}

static int64_t GetIntArg(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    const std::string& key) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (!args) return 0;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return 0;
  if (const auto* v32 = std::get_if<int32_t>(&it->second)) return *v32;
  if (const auto* v64 = std::get_if<int64_t>(&it->second)) return *v64;
  return 0;
}

// ══════════════════════════════════════════════════════════════════
// NativeVideoPlayer
// ══════════════════════════════════════════════════════════════════

NativeVideoPlayer::NativeVideoPlayer(flutter::TextureRegistrar* registrar)
    : texture_registrar_(registrar) {
  MFStartup(MF_VERSION);
  InitD3D();
  InitMediaEngine();
}

NativeVideoPlayer::~NativeVideoPlayer() { Dispose(); }

// ── D3D11 初始化 / D3D11 initialization ──

bool NativeVideoPlayer::InitD3D() {
  D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0};
  D3D_FEATURE_LEVEL actual;
  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT |
               D3D11_CREATE_DEVICE_VIDEO_SUPPORT;
  HRESULT hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels, 1,
      D3D11_SDK_VERSION, d3d_device_.ReleaseAndGetAddressOf(),
      &actual, d3d_context_.ReleaseAndGetAddressOf());
  if (FAILED(hr)) return false;

  // Enable multi-threaded access
  ComPtr<ID3D10Multithread> mt;
  d3d_device_.As(&mt);
  if (mt) mt->SetMultithreadProtected(TRUE);

  hr = MFCreateDXGIDeviceManager(&reset_token_,
                                  dxgi_manager_.ReleaseAndGetAddressOf());
  if (FAILED(hr)) return false;

  hr = dxgi_manager_->ResetDevice(d3d_device_.Get(), reset_token_);
  return SUCCEEDED(hr);
}

// ── 媒体引擎初始化 / Media engine initialization ──

bool NativeVideoPlayer::InitMediaEngine() {
  ComPtr<IMFMediaEngineClassFactory> factory;
  HRESULT hr = CoCreateInstance(CLSID_MFMediaEngineClassFactory, nullptr,
                                 CLSCTX_ALL, IID_PPV_ARGS(&factory));
  if (FAILED(hr)) return false;

  auto notify = new MediaEngineNotify(
      [this](DWORD e, DWORD_PTR p1, DWORD p2) { OnMediaEvent(e, p1, p2); });

  ComPtr<IMFAttributes> attrs;
  MFCreateAttributes(attrs.GetAddressOf(), 3);
  attrs->SetUnknown(MF_MEDIA_ENGINE_CALLBACK, notify);
  attrs->SetUnknown(MF_MEDIA_ENGINE_DXGI_MANAGER, dxgi_manager_.Get());
  attrs->SetUINT32(MF_MEDIA_ENGINE_VIDEO_OUTPUT_FORMAT,
                    DXGI_FORMAT_B8G8R8A8_UNORM);

  hr = factory->CreateInstance(MF_MEDIA_ENGINE_WAITFORSTABLE_STATE,
                                attrs.Get(),
                                media_engine_.ReleaseAndGetAddressOf());
  notify->Release();
  return SUCCEEDED(hr);
}

// ── 确保渲染目标纹理尺寸匹配 / Ensure render target texture matches size ──

bool NativeVideoPlayer::EnsureRenderTarget(UINT w, UINT h) {
  if (video_w_ == w && video_h_ == h && staging_tex_) return true;
  video_w_ = w;
  video_h_ = h;

  D3D11_TEXTURE2D_DESC desc = {};
  desc.Width = w;
  desc.Height = h;
  desc.MipLevels = 1;
  desc.ArraySize = 1;
  desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  desc.SampleDesc.Count = 1;
  desc.Usage = D3D11_USAGE_DEFAULT;
  desc.BindFlags = D3D11_BIND_RENDER_TARGET;

  HRESULT hr = d3d_device_->CreateTexture2D(
      &desc, nullptr, render_tex_.ReleaseAndGetAddressOf());
  if (FAILED(hr)) return false;

  desc.Usage = D3D11_USAGE_STAGING;
  desc.BindFlags = 0;
  desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  hr = d3d_device_->CreateTexture2D(
      &desc, nullptr, staging_tex_.ReleaseAndGetAddressOf());
  if (FAILED(hr)) return false;

  std::lock_guard<std::mutex> lock(buf_mutex_);
  pixel_data_.resize(static_cast<size_t>(w) * h * 4);
  pixel_buf_.buffer = pixel_data_.data();
  pixel_buf_.width = w;
  pixel_buf_.height = h;
  return true;
}

// ── 媒体引擎事件处理 / Media engine event handling ──

void NativeVideoPlayer::OnMediaEvent(DWORD event, DWORD_PTR, DWORD) {
  switch (event) {
    case MF_MEDIA_ENGINE_EVENT_LOADEDMETADATA: {
      double dur = media_engine_->GetDuration();
      if (!isinf(dur) && !isnan(dur)) {
        SendEvent("duration",
                  flutter::EncodableValue(static_cast<int>(dur * 1000)));
      }
      SendEvent("buffering", flutter::EncodableValue(false));
      break;
    }
    case MF_MEDIA_ENGINE_EVENT_PLAYING:
      SendEvent("playing", flutter::EncodableValue(true));
      StartFrameTimer();
      break;
    case MF_MEDIA_ENGINE_EVENT_PAUSE:
      SendEvent("playing", flutter::EncodableValue(false));
      break;
    case MF_MEDIA_ENGINE_EVENT_ENDED:
      StopFrameTimer();
      SendEvent("completed", flutter::EncodableValue(nullptr));
      break;
    case MF_MEDIA_ENGINE_EVENT_ERROR:
      SendEvent("error",
                flutter::EncodableValue(std::string("Media engine error")));
      break;
    case MF_MEDIA_ENGINE_EVENT_BUFFERINGSTARTED:
      SendEvent("buffering", flutter::EncodableValue(true));
      break;
    case MF_MEDIA_ENGINE_EVENT_BUFFERINGENDED:
      SendEvent("buffering", flutter::EncodableValue(false));
      break;
    default:
      break;
  }
}

// ── 帧更新：从媒体引擎提取帧到 CPU 缓冲 / Frame update: extract frame to CPU buffer ──

void NativeVideoPlayer::UpdateFrame() {
  if (!media_engine_ || !media_engine_->HasVideo()) return;

  // 每 12 帧发送一次位置（约 200ms @60fps）/ Send position every ~200ms
  frame_count_++;
  if (frame_count_ % 12 == 0) {
    double t = media_engine_->GetCurrentTime();
    SendEvent("position",
              flutter::EncodableValue(static_cast<int>(t * 1000)));
  }

  LONGLONG pts;
  if (media_engine_->OnVideoStreamTick(&pts) != S_OK) return;

  DWORD w = 0, h = 0;
  media_engine_->GetNativeVideoSize(&w, &h);
  if (w == 0 || h == 0) return;
  if (!EnsureRenderTarget(w, h)) return;

  MFVideoNormalizedRect src = {0.0f, 0.0f, 1.0f, 1.0f};
  RECT dst = {0, 0, static_cast<LONG>(w), static_cast<LONG>(h)};
  MFARGB border = {0, 0, 0, 255};

  HRESULT hr =
      media_engine_->TransferVideoFrame(render_tex_.Get(), &src, &dst, &border);
  if (FAILED(hr)) return;

  d3d_context_->CopyResource(staging_tex_.Get(), render_tex_.Get());

  D3D11_MAPPED_SUBRESOURCE mapped;
  hr = d3d_context_->Map(staging_tex_.Get(), 0, D3D11_MAP_READ, 0, &mapped);
  if (FAILED(hr)) return;

  {
    std::lock_guard<std::mutex> lock(buf_mutex_);
    const uint8_t* src_data = static_cast<const uint8_t*>(mapped.pData);
    for (UINT row = 0; row < h; row++) {
      memcpy(pixel_data_.data() + row * w * 4,
             src_data + row * mapped.RowPitch, w * 4);
    }
  }
  d3d_context_->Unmap(staging_tex_.Get(), 0);
  texture_registrar_->MarkTextureFrameAvailable(texture_id_);
}

// ── 帧定时器 / Frame timer ──

void NativeVideoPlayer::StartFrameTimer() {
  StopFrameTimer();
  CreateTimerQueueTimer(&timer_handle_, nullptr, OnTimer, this, 0, 16,
                         WT_EXECUTEDEFAULT);
}

void NativeVideoPlayer::StopFrameTimer() {
  if (timer_handle_) {
    DeleteTimerQueueTimer(nullptr, timer_handle_, INVALID_HANDLE_VALUE);
    timer_handle_ = nullptr;
  }
}

void CALLBACK NativeVideoPlayer::OnTimer(PVOID ctx, BOOLEAN) {
  static_cast<NativeVideoPlayer*>(ctx)->UpdateFrame();
}

// ── 事件发送 / Event sending ──

void NativeVideoPlayer::SendEvent(const std::string& name,
                                   const flutter::EncodableValue& val) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  if (!event_sink_) return;
  flutter::EncodableMap m;
  m[flutter::EncodableValue("event")] = flutter::EncodableValue(name);
  m[flutter::EncodableValue("value")] = val;
  event_sink_->Success(flutter::EncodableValue(m));
}

void NativeVideoPlayer::SetEventSink(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  event_sink_ = std::move(sink);
}

// ── 播放控制 / Playback control ──

int64_t NativeVideoPlayer::Create() {
  pixel_texture_ = std::make_unique<flutter::PixelBufferTexture>(
      [this](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
        std::lock_guard<std::mutex> lock(buf_mutex_);
        if (!pixel_buf_.buffer) return nullptr;
        return &pixel_buf_;
      });
  texture_id_ = texture_registrar_->RegisterTexture(pixel_texture_.get());
  return texture_id_;
}

void NativeVideoPlayer::Open(const std::string& url) {
  if (!media_engine_) return;
  BSTR bstr = SysAllocString(Utf8ToWide(url).c_str());
  media_engine_->SetSource(bstr);
  SysFreeString(bstr);
  media_engine_->Load();
  SendEvent("buffering", flutter::EncodableValue(true));
}

void NativeVideoPlayer::Play() {
  if (media_engine_) media_engine_->Play();
}

void NativeVideoPlayer::Pause() {
  if (media_engine_) media_engine_->Pause();
}

void NativeVideoPlayer::Seek(int64_t ms) {
  if (media_engine_) media_engine_->SetCurrentTime(ms / 1000.0);
}

void NativeVideoPlayer::SetVolume(double v) {
  if (media_engine_) media_engine_->SetVolume(v);
}

void NativeVideoPlayer::SetSpeed(double s) {
  if (media_engine_) media_engine_->SetPlaybackRate(s);
}

void NativeVideoPlayer::Dispose() {
  Cleanup();
  if (texture_id_ != -1 && texture_registrar_) {
    texture_registrar_->UnregisterTexture(texture_id_);
    texture_id_ = -1;
  }
}

void NativeVideoPlayer::Cleanup() {
  StopFrameTimer();
  if (media_engine_) {
    media_engine_->Shutdown();
    media_engine_.Reset();
  }
  render_tex_.Reset();
  staging_tex_.Reset();
  video_w_ = 0;
  video_h_ = 0;
}

// ══════════════════════════════════════════════════════════════════
// FlutterCacheVideoPlayerPlugin
// ══════════════════════════════════════════════════════════════════

/// EventChannel 流处理器辅助类 / EventChannel stream handler helper.
class EventHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
 public:
  using ListenCb = std::function<void(
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>)>;
  using CancelCb = std::function<void()>;

  EventHandler(ListenCb on_listen, CancelCb on_cancel)
      : on_listen_(std::move(on_listen)),
        on_cancel_(std::move(on_cancel)) {}

 protected:
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnListenInternal(
      const flutter::EncodableValue*,
      std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
      override {
    on_listen_(std::move(events));
    return nullptr;
  }
  std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
  OnCancelInternal(const flutter::EncodableValue*) override {
    on_cancel_();
    return nullptr;
  }

 private:
  ListenCb on_listen_;
  CancelCb on_cancel_;
};

void FlutterCacheVideoPlayerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<FlutterCacheVideoPlayerPlugin>(
      registrar->texture_registrar(), registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

FlutterCacheVideoPlayerPlugin::FlutterCacheVideoPlayerPlugin(
    flutter::TextureRegistrar* tex, flutter::BinaryMessenger* messenger) {
  player_ = std::make_unique<NativeVideoPlayer>(tex);

  method_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "flutter_cache_video_player/player",
          &flutter::StandardMethodCodec::GetInstance());
  method_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  event_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          messenger, "flutter_cache_video_player/player/events",
          &flutter::StandardMethodCodec::GetInstance());

  auto* p = player_.get();
  event_channel_->SetStreamHandler(std::make_unique<EventHandler>(
      [p](auto sink) { p->SetEventSink(std::move(sink)); },
      [p]() { p->SetEventSink(nullptr); }));
}

FlutterCacheVideoPlayerPlugin::~FlutterCacheVideoPlayerPlugin() = default;

void FlutterCacheVideoPlayerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = call.method_name();

  if (method == "create") {
    result->Success(flutter::EncodableValue(player_->Create()));
  } else if (method == "open") {
    player_->Open(GetStringArg(call, "url"));
    result->Success();
  } else if (method == "play") {
    player_->Play();
    result->Success();
  } else if (method == "pause") {
    player_->Pause();
    result->Success();
  } else if (method == "seek") {
    player_->Seek(GetIntArg(call, "position"));
    result->Success();
  } else if (method == "setVolume") {
    player_->SetVolume(GetDoubleArg(call, "volume"));
    result->Success();
  } else if (method == "setSpeed") {
    player_->SetSpeed(GetDoubleArg(call, "speed"));
    result->Success();
  } else if (method == "dispose") {
    player_->Dispose();
    result->Success();
  } else if (method == "getPlatformVersion") {
    std::ostringstream v;
    v << "Windows ";
    if (IsWindows10OrGreater())
      v << "10+";
    else if (IsWindows8OrGreater())
      v << "8";
    else if (IsWindows7OrGreater())
      v << "7";
    result->Success(flutter::EncodableValue(v.str()));
  } else {
    result->NotImplemented();
  }
}

}  // namespace flutter_cache_video_player
