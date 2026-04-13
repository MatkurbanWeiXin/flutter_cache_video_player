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

// 自定义窗口消息，用于通知平台线程分发事件。
// Custom window message to notify the platform thread to drain pending events.
static constexpr UINT WM_DRAIN_EVENTS = WM_APP + 0x100;

// SetTimer ID，用于驱动 PollAndRender 的 WM_TIMER 消息。
// SetTimer ID for WM_TIMER messages driving PollAndRender.
static constexpr UINT_PTR kFrameTimerId = 1;

// ── 隐藏消息窗口 / Hidden message-only window ──
//
// 不依赖 Flutter 的 TopLevelWindowProcDelegate 转发 WM_TIMER / WM_DRAIN_EVENTS，
// 而是创建一个我们完全控制的 HWND_MESSAGE 隐藏窗口。
// SetTimer 和 PostMessage 目标均为该窗口，确保消息可靠送达。
// Instead of relying on Flutter's TopLevelWindowProcDelegate to forward
// WM_TIMER / WM_DRAIN_EVENTS, we create a hidden HWND_MESSAGE window that
// we fully control. SetTimer and PostMessage target this window so messages
// are reliably delivered.

static constexpr wchar_t kMsgWindowClass[] =
    L"FlutterCacheVideoPlayerMsg";

static LRESULT CALLBACK MsgWndProc(HWND hwnd, UINT message,
                                    WPARAM wparam, LPARAM lparam) {
  auto* player = reinterpret_cast<NativeVideoPlayer*>(
      GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (player) {
    if (message == WM_TIMER && wparam == kFrameTimerId) {
      player->PollAndRender();
      return 0;
    }
    if (message == WM_DRAIN_EVENTS) {
      player->DrainEvents();
      return 0;
    }
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

NativeVideoPlayer::NativeVideoPlayer(flutter::TextureRegistrar* registrar,
                                      HWND hwnd)
    : texture_registrar_(registrar) {
  // GetView()->GetNativeWindow() 返回的是 FlutterView 子窗口，但
  // RegisterTopLevelWindowProcDelegate 回调在顶层窗口的 WndProc 中触发。
  // 必须 PostMessage 到顶层祖先窗口，否则消息永远到达不了我们的 delegate。
  // GetView()->GetNativeWindow() returns the FlutterView child HWND, but
  // TopLevelWindowProcDelegate hooks fire in the top-level window's WndProc.
  // PostMessage must target the top-level ancestor, or our delegate never sees it.
  hwnd_ = GetAncestor(hwnd, GA_ROOT);
  if (!hwnd_) hwnd_ = hwnd;
  platform_thread_id_ = GetCurrentThreadId();

  // 创建隐藏消息窗口，拥有定时器和接收跨线程 PostMessage。
  // Create hidden message-only window to own timers and receive cross-thread PostMessage.
  static bool class_registered = false;
  if (!class_registered) {
    WNDCLASSEXW wc = {};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = MsgWndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = kMsgWindowClass;
    RegisterClassExW(&wc);
    class_registered = true;
  }
  msg_hwnd_ = CreateWindowExW(0, kMsgWindowClass, L"", 0,
                               0, 0, 0, 0, HWND_MESSAGE,
                               nullptr, GetModuleHandle(nullptr), nullptr);
  SetWindowLongPtr(msg_hwnd_, GWLP_USERDATA,
                   reinterpret_cast<LONG_PTR>(this));

  // Flutter runner already called CoInitializeEx (STA). Don't override.
  MFStartup(MF_VERSION);
  if (!InitD3D()) {
    SendEvent("error", flutter::EncodableValue("Failed to initialize D3D11"));
    return;
  }
  if (!InitMediaEngine()) {
    SendEvent("error", flutter::EncodableValue("Failed to initialize Media Engine"));
    return;
  }
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
  if (FAILED(hr)) {
    // Fallback: retry without VIDEO_SUPPORT flag (some GPUs/drivers lack it)
    flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
    hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, flags, levels, 1,
        D3D11_SDK_VERSION, d3d_device_.ReleaseAndGetAddressOf(),
        &actual, d3d_context_.ReleaseAndGetAddressOf());
    if (FAILED(hr)) return false;
  }

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

  hr = factory->CreateInstance(0, attrs.Get(),
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

// ── 媒体引擎事件回调（仅保留接口） / Media engine event callback (interface-only) ──

void NativeVideoPlayer::OnMediaEvent(DWORD event, DWORD_PTR p1, DWORD p2) {
  // 安全网：如果仍以 WAITFORSTABLE_STATE 模式创建，立即解除阻塞。
  // Safety net: if engine was created with WAITFORSTABLE_STATE, unblock it.
  if (event == MF_MEDIA_ENGINE_EVENT_NOTIFYSTABLESTATE) {
    HANDLE h = reinterpret_cast<HANDLE>(p1);
    if (h) SetEvent(h);
    return;
  }

  // 媒体引擎报告错误时立即上报 Dart 端。
  // When the media engine reports an error, forward it to Dart immediately.
  if (event == MF_MEDIA_ENGINE_EVENT_ERROR) {
    auto code = static_cast<int>(p1);
    std::ostringstream oss;
    oss << "MediaEngine error: code=" << code
        << ", hr=0x" << std::hex << p2;
    SendEvent("error", flutter::EncodableValue(oss.str()));
  }
}

// ── 定时器轮询：检测引擎状态变化并提取帧 / Timer poll: detect engine state changes and extract frames ──

void NativeVideoPlayer::PollAndRender() {
  if (!media_engine_) return;

  // 1. 检查错误 / Check for error
  ComPtr<IMFMediaError> err;
  media_engine_->GetError(&err);
  if (err) {
    USHORT code = err->GetErrorCode();
    std::string msg =
        "MediaEngine error code: " + std::to_string(static_cast<int>(code));
    SendEvent("error", flutter::EncodableValue(msg));
    return;
  }

  USHORT readyState = media_engine_->GetReadyState();

  // 2. 时长（元数据可用后发送一次）/ Duration (once, when metadata available)
  if (!duration_sent_ && readyState >= MF_MEDIA_ENGINE_READY_HAVE_METADATA) {
    double dur = media_engine_->GetDuration();
    if (!isinf(dur) && !isnan(dur) && dur > 0) {
      SendEvent("duration",
                flutter::EncodableValue(static_cast<int>(dur * 1000)));
      duration_sent_ = true;
    }
  }

  // 3. 播放状态（仅在已获取数据后才有意义，避免在加载阶段误报 playing=true）
  // Playing state – only meaningful after media has data.
  // IsPaused()==FALSE right after Play() even before any data is loaded;
  // reporting playing=true prematurely defeats the Dart _hasPlayedSinceOpen guard.
  if (readyState >= MF_MEDIA_ENGINE_READY_HAVE_CURRENT_DATA) {
    bool playing = (media_engine_->IsPaused() == FALSE);
    if (playing != last_playing_) {
      SendEvent("playing", flutter::EncodableValue(playing));
      last_playing_ = playing;
    }
  }

  // 4. 缓冲状态 / Buffering state
  bool buffering =
      !duration_sent_ ||
      readyState < MF_MEDIA_ENGINE_READY_HAVE_FUTURE_DATA;
  if (buffering != last_buffering_) {
    SendEvent("buffering", flutter::EncodableValue(buffering));
    last_buffering_ = buffering;
  }

  // 5. 播放结束（仅在元数据已就绪后才有意义，防止加载失败时误报完成）
  // Ended – only meaningful after duration was received (media actually loaded).
  bool ended = (media_engine_->IsEnded() != FALSE);
  if (ended && !last_ended_ && duration_sent_) {
    SendEvent("completed", flutter::EncodableValue(nullptr));
    last_ended_ = true;
    return;
  }

  // 6. 帧提取 / Frame extraction
  if (!media_engine_->HasVideo()) return;

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

// ── 帧定时器（基于窗口消息循环）/ Frame timer (window message loop based) ──
//
// 使用 SetTimer 而非 CreateTimerQueueTimer，使 PollAndRender 在平台线程上
// 通过 WM_TIMER 消息执行。这样 SendEvent 可直接访问 EventSink，
// 无需跨线程 PostMessage + DrainEvents。
// Uses SetTimer instead of CreateTimerQueueTimer so PollAndRender runs on the
// platform thread via WM_TIMER. SendEvent can access EventSink directly
// without cross-thread PostMessage + DrainEvents.

void NativeVideoPlayer::StartFrameTimer() {
  StopFrameTimer();
  ::SetTimer(msg_hwnd_, kFrameTimerId, 16, nullptr);
}

void NativeVideoPlayer::StopFrameTimer() {
  ::KillTimer(msg_hwnd_, kFrameTimerId);
}

// ── 事件发送（线程安全） / Thread-safe event sending ──
//
// 平台线程：直接通过 EventSink 发送。
// 后台线程：入队 + PostMessage 弹回平台线程，由 WndProc 合约分发。
// Platform thread: sends via EventSink directly.
// Background thread: enqueues + PostMessage bounces to the platform thread,
//   where WndProc delegate drains and delivers events.

void NativeVideoPlayer::SendEvent(const std::string& name,
                                   const flutter::EncodableValue& val) {
  flutter::EncodableMap m;
  m[flutter::EncodableValue("event")] = flutter::EncodableValue(name);
  m[flutter::EncodableValue("value")] = val;
  auto ev = flutter::EncodableValue(std::move(m));

  if (GetCurrentThreadId() == platform_thread_id_) {
    // 已在平台线程上，直接发送。
    // Already on the platform thread — send directly.
    std::lock_guard<std::mutex> lock(sink_mutex_);
    if (event_sink_) event_sink_->Success(ev);
    return;
  }

  // 后台线程：入队后通过 PostMessage 通知平台线程分发。
  // Background thread: enqueue and notify platform thread via PostMessage.
  {
    std::lock_guard<std::mutex> lock(event_queue_mutex_);
    pending_events_.push(std::move(ev));
  }
  PostMessage(msg_hwnd_, WM_DRAIN_EVENTS, 0, 0);
}

void NativeVideoPlayer::DrainEvents() {
  std::queue<flutter::EncodableValue> snapshot;
  {
    std::lock_guard<std::mutex> lock(event_queue_mutex_);
    std::swap(snapshot, pending_events_);
  }
  std::lock_guard<std::mutex> lock(sink_mutex_);
  while (!snapshot.empty()) {
    if (event_sink_) event_sink_->Success(snapshot.front());
    snapshot.pop();
  }
}

void NativeVideoPlayer::SetEventSink(
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink) {
  std::lock_guard<std::mutex> lock(sink_mutex_);
  event_sink_ = std::move(sink);
}

// ── 播放控制 / Playback control ──

int64_t NativeVideoPlayer::Create() {
  texture_variant_ = std::make_unique<flutter::TextureVariant>(
      flutter::PixelBufferTexture(
          [this](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
            std::lock_guard<std::mutex> lock(buf_mutex_);
            if (!pixel_buf_.buffer) return nullptr;
            return &pixel_buf_;
          }));
  texture_id_ = texture_registrar_->RegisterTexture(texture_variant_.get());
  return texture_id_;
}

void NativeVideoPlayer::Open(const std::string& url) {
  if (!media_engine_) return;

  // 切换源时重置状态 / Reset state on source switch
  StopFrameTimer();
  frame_count_ = 0;
  video_w_ = 0;
  video_h_ = 0;
  duration_sent_ = false;
  last_buffering_ = true;
  last_playing_ = false;
  last_ended_ = false;

  BSTR bstr = SysAllocString(Utf8ToWide(url).c_str());
  HRESULT hr = media_engine_->SetSource(bstr);
  SysFreeString(bstr);
  if (FAILED(hr)) {
    std::ostringstream oss;
    oss << "SetSource failed: hr=0x" << std::hex << hr;
    SendEvent("error", flutter::EncodableValue(oss.str()));
    return;
  }

  hr = media_engine_->Load();
  if (FAILED(hr)) {
    std::ostringstream oss;
    oss << "Load failed: hr=0x" << std::hex << hr;
    SendEvent("error", flutter::EncodableValue(oss.str()));
    return;
  }

  // Load 后立即调用 Play()，媒体引擎会在准备就绪后自动开始播放。
  // Call Play() right after Load(). The media engine will auto-play once ready.
  media_engine_->Play();

  // 通知 Dart 端正在缓冲 / Notify Dart that buffering has started
  SendEvent("buffering", flutter::EncodableValue(true));
  StartFrameTimer();
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
  if (msg_hwnd_) {
    SetWindowLongPtr(msg_hwnd_, GWLP_USERDATA, 0);
    DestroyWindow(msg_hwnd_);
    msg_hwnd_ = nullptr;
  }
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
      registrar, registrar->texture_registrar(), registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

FlutterCacheVideoPlayerPlugin::FlutterCacheVideoPlayerPlugin(
    flutter::PluginRegistrarWindows* registrar,
    flutter::TextureRegistrar* tex, flutter::BinaryMessenger* messenger)
    : registrar_(registrar) {
  HWND hwnd = registrar->GetView()->GetNativeWindow();
  player_ = std::make_unique<NativeVideoPlayer>(tex, hwnd);

  // 注册窗口消息回调，处理来自后台线程的事件分发请求。
  // Register window proc delegate to drain events posted from background threads.
  window_proc_id_ = registrar->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowMessage(hwnd, message, wparam, lparam);
      });

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

FlutterCacheVideoPlayerPlugin::~FlutterCacheVideoPlayerPlugin() {
  if (window_proc_id_ != -1 && registrar_) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
}

std::optional<LRESULT> FlutterCacheVideoPlayerPlugin::HandleWindowMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  // 定时器和事件分发已由 NativeVideoPlayer 的隐藏消息窗口处理。
  // Timer and event dispatch are handled by NativeVideoPlayer's hidden msg window.
  return std::nullopt;
}

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
