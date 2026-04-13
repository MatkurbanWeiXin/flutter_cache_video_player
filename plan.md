# 🎬 Flutter 6 端通用 — 边看边缓存音视频播放器（原生播放器方案）

> **技术栈**: `tostore ^3.1.0` · `breakpoint ^1.3.2` · `原生播放引擎` · `shelf ^1.4` · `dio ^5.x` · Dart Isolate
> **播放引擎**: Android: ExoPlayer (Media3) · iOS/macOS: AVPlayer · Windows: Media Foundation · Linux: GStreamer · Web: HTML5 `<video>`
> **目标平台**: Android · iOS · Windows · macOS · Linux · Web
> **最后更新**: 2026-06-12

---

## 一、架构总览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              UI 层 (breakpoint)                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ MobileLayout  │  │ TabletLayout │  │DesktopLayout │  │  ThemeEngine  │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  └───────────────┘  │
│         └──────────────────┴────────────────┘                              │
│                             │                                              │
│              ┌──────────────┴──────────────┐                               │
│              │ Texture(textureId) Widget   │  ← 原生纹理渲染，非第三方       │
│              └──────────────┬──────────────┘                               │
├─────────────────────────────┼──────────────────────────────────────────────┤
│                        播放控制层                                           │
│  ┌──────────────────────────┴──────────────────────────────────────────┐   │
│  │        PlayerService (NativePlayerController + MethodChannel)       │   │
│  │                                                                     │   │
│  │  Dart ──MethodChannel──► 原生播放器 (ExoPlayer/AVPlayer/MF/GST)     │   │
│  │  Dart ◄──EventChannel──  位置/时长/缓冲/错误/播放状态 事件流           │   │
│  └──────────────────────────┬──────────────────────────────────────────┘   │
│                              │ http://127.0.0.1:{port}/stream?url=...     │
├──────────────────────────────┼─────────────────────────────────────────────┤
│                         代理缓存层 (主 Isolate)                             │
│  ┌──────────────────────────┴──────────────────────────────────────────┐   │
│  │                    ProxyCacheServer (shelf)                          │   │
│  │  ┌─────────────────┐   ┌────────────────┐   ┌──────────────────┐   │   │
│  │  │  RangeParser     │   │ CacheRouter    │   │ ResponseBuilder  │   │   │
│  │  └─────────────────┘   └────────┬───────┘   └──────────────────┘   │   │
│  └─────────────────────────────────┼──────────────────────────────────┘   │
│                                    │ SendPort / ReceivePort                │
├────────────────────────────────────┼──────────────────────────────────────┤
│                        下载 Isolate 池 (后台线程)                           │
│  ┌─────────────────────────────────┴─────────────────────────────────┐    │
│  │           DownloadWorkerPool (N 个 Isolate)                        │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │    │
│  │  │ Worker-1 │  │ Worker-2 │  │ Worker-N │  │ ChunkMerger      │  │    │
│  │  │ (dio)    │  │ (dio)    │  │ (dio)    │  │ (顺序合并碎片)    │  │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────────────┘  │    │
│  └───────────────────────────────────────────────────────────────────┘    │
│                                    │                                       │
├────────────────────────────────────┼──────────────────────────────────────┤
│                            数据持久层 (tostore)                            │
│  ┌─────────────────────────────────┴─────────────────────────────────┐    │
│  │                 CacheIndexDB (tostore)                             │    │
│  │  ┌──────────────┐  ┌───────────────┐  ┌────────────────────┐     │    │
│  │  │ media_index   │  │ chunk_bitmap  │  │ playback_history   │     │    │
│  │  │ 表            │  │ 表            │  │ 表                 │     │    │
│  │  └──────────────┘  └───────────────┘  └────────────────────┘     │    │
│  └───────────────────────────────────────────────────────────────────┘    │
│                                    │                                       │
│                              本地文件系统                                   │
│                     /{app_cache}/media/{hash}/data.bin                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.1 原生播放引擎选型（替代 media_kit）

| 平台        | 原生引擎                           | 渲染方式                           | 优势                                            |
|-----------|--------------------------------|--------------------------------|-----------------------------------------------|
| **Android** | ExoPlayer (Media3)             | TextureRegistry + SurfaceTexture | Google 官方、硬件解码、自适应比特率、DRM 支持                   |
| **iOS**     | AVPlayer (AVFoundation)        | FlutterTexture + CVPixelBuffer  | Apple 官方、零额外依赖、硬件加速、低功耗                        |
| **macOS**   | AVPlayer (AVFoundation)        | FlutterTexture + CVPixelBuffer  | 与 iOS 共享 90% 代码、Apple Silicon 原生支持              |
| **Windows** | Media Foundation (IMFMediaEngine) | TextureRegistry + ID3D11Texture2D | 系统自带、零外部 DLL、硬件解码、Windows 7+ 兼容              |
| **Linux**   | GStreamer (playbin3)           | TextureRegistry + GL texture    | 系统自带、codec 生态丰富、硬件解码（VA-API/VDPAU）           |
| **Web**     | HTML5 `<video>`                | HtmlElementView                 | 浏览器原生、零 WASM、最优性能                             |

### 1.2 Dart ↔ 原生通信架构

```
┌───────────────────────────────────────────────────────────────┐
│                        Dart 侧                                │
│                                                               │
│  NativePlayerController                                       │
│  ├── MethodChannel("flutter_cache_video_player/player")       │
│  │   ├── create()          → int textureId                    │
│  │   ├── open(url)         → void                             │
│  │   ├── play()            → void                             │
│  │   ├── pause()           → void                             │
│  │   ├── seek(positionMs)  → void                             │
│  │   ├── setVolume(0~1.0)  → void                             │
│  │   ├── setSpeed(rate)    → void                             │
│  │   └── dispose()         → void                             │
│  │                                                             │
│  └── EventChannel("flutter_cache_video_player/player/events") │
│      └── Stream<Map> →                                         │
│          {"event": "position",  "value": 12345}                │
│          {"event": "duration",  "value": 180000}               │
│          {"event": "playing",   "value": true}                 │
│          {"event": "buffering", "value": false}                │
│          {"event": "error",     "value": "..."}                │
│          {"event": "completed"}                                │
└───────────────────────────────────────────────────────────────┘
```

---

## 二、目录结构

```
lib/
├── flutter_cache_video_player.dart    # 公共 API barrel 导出
├── src/
│   ├── cache_video_player.dart        # 插件主入口 & 全层协调
│   │
│   ├── core/
│   │   ├── constants.dart             # 全局常量（块大小、最大并发数等）
│   │   ├── platform_detector.dart     # kIsWeb / Platform 检测
│   │   └── logger.dart                # 统一日志
│   │
│   ├── data/
│   │   ├── cache_index_db.dart        # tostore 数据库初始化 & 表定义
│   │   ├── models/
│   │   │   ├── media_index.dart       # 媒体索引模型
│   │   │   ├── chunk_bitmap.dart      # 分块位图模型
│   │   │   └── playback_history.dart  # 播放历史模型
│   │   └── repositories/
│   │       ├── cache_repository.dart  # 缓存读写抽象
│   │       └── history_repository.dart# 播放历史读写
│   │
│   ├── download/
│   │   ├── download_worker_pool.dart  # Isolate 线程池管理器
│   │   ├── download_worker.dart       # 单个 Worker Isolate 入口
│   │   ├── download_task.dart         # 下载任务消息定义
│   │   ├── chunk_merger.dart          # 碎片合并器
│   │   └── download_manager.dart      # 统一调度（取消/暂停/恢复/优先级）
│   │
│   ├── proxy/
│   │   ├── proxy_server.dart          # shelf 本地代理主逻辑
│   │   ├── range_handler.dart         # HTTP Range 请求解析与响应
│   │   ├── stream_splitter.dart       # 流"一分二"(播放器 + 磁盘)
│   │   └── mime_detector.dart         # MIME 类型检测
│   │
│   ├── player/
│   │   ├── native_player_controller.dart  # 原生播放器控制器（MethodChannel + EventChannel）
│   │   ├── player_service.dart            # 播放服务（基于 NativePlayerController）
│   │   ├── player_state.dart              # 播放器状态管理（ChangeNotifier）
│   │   ├── playlist_manager.dart          # 播放列表 & 预加载
│   │   └── platform_player_factory.dart   # Web 降级 / Native 代理选择
│   │
│   ├── ui/
│   │   ├── layouts/
│   │   │   ├── mobile_layout.dart     # 手机布局
│   │   │   ├── tablet_layout.dart     # 平板布局
│   │   │   └── desktop_layout.dart    # 桌面布局
│   │   ├── widgets/
│   │   │   ├── video_player_widget.dart   # Texture 原生渲染组件
│   │   │   ├── audio_player_widget.dart   # 纯音频 UI
│   │   │   ├── progress_bar.dart          # 含缓存指示器的进度条
│   │   │   ├── cache_indicator.dart       # 缓存位图可视化
│   │   │   ├── playlist_panel.dart        # 播放列表面板
│   │   │   └── settings_sheet.dart        # 设置面板
│   │   ├── themes/
│   │   │   ├── light_theme.dart
│   │   │   ├── dark_theme.dart
│   │   │   └── theme_controller.dart
│   │   └── responsive/
│   │       └── adaptive_scaffold.dart
│   │
│   └── utils/
│       ├── url_hasher.dart            # URL → 稳定文件名哈希
│       ├── file_utils.dart            # 平台安全的文件路径
│       └── size_formatter.dart        # 字节 → 可读大小

android/src/main/kotlin/com/kurban/flutter_cache_video_player/
├── FlutterCacheVideoPlayerPlugin.kt   # 插件注册 + MethodChannel/EventChannel
├── NativeVideoPlayer.kt              # ExoPlayer (Media3) 封装
└── TextureRenderer.kt                # SurfaceTexture → TextureRegistry 桥接

ios/flutter_cache_video_player/Sources/flutter_cache_video_player/
├── FlutterCacheVideoPlayerPlugin.swift  # 插件注册 + Channel
├── NativeVideoPlayer.swift              # AVPlayer 封装
└── TextureRenderer.swift                # CVPixelBuffer → FlutterTexture 桥接

macos/flutter_cache_video_player/Sources/flutter_cache_video_player/
├── FlutterCacheVideoPlayerPlugin.swift  # 插件注册 + Channel
├── NativeVideoPlayer.swift              # AVPlayer 封装（共享 iOS 90% 代码）
└── TextureRenderer.swift                # CVPixelBuffer → FlutterTexture 桥接

windows/
├── flutter_cache_video_player_plugin.h          # 插件头文件
├── flutter_cache_video_player_plugin.cpp        # 插件注册 + Channel
├── native_video_player.h                        # Media Foundation 封装声明
├── native_video_player.cpp                      # Media Foundation (IMFMediaEngine) 实现
├── texture_renderer.h                           # Texture 桥接声明
├── texture_renderer.cpp                         # D3D11 Texture → TextureRegistry
├── flutter_cache_video_player_plugin_c_api.cpp  # C API 入口
└── include/flutter_cache_video_player/
    └── flutter_cache_video_player_plugin_c_api.h

linux/
├── flutter_cache_video_player_plugin.cc          # 插件注册 + Channel
├── flutter_cache_video_player_plugin_private.h   # 内部头文件
├── native_video_player.cc                        # GStreamer (playbin3) 实现
├── native_video_player.h                         # GStreamer 封装声明
├── texture_renderer.cc                           # GL texture → TextureRegistry
├── texture_renderer.h                            # Texture 桥接声明
└── include/flutter_cache_video_player/
    └── flutter_cache_video_player_plugin.h
```

---

## 三、核心模块详细设计

### 3.1 数据持久层 — `tostore`

#### 3.1.1 表结构

| 表名                   | 字段                 | 类型          | 说明                          |
|----------------------|--------------------|-------------|-----------------------------|
| **media_index**      | `url_hash` (PK)    | `String`    | URL 的 SHA-256 前 16 位        |
|                      | `original_url`     | `String`    | 原始资源 URL                    |
|                      | `local_dir`        | `String`    | 本地缓存目录路径                    |
|                      | `total_bytes`      | `int`       | 资源总大小（字节）                   |
|                      | `mime_type`        | `String`    | `video/mp4`, `audio/mpeg` 等 |
|                      | `is_completed`     | `bool`      | 是否全量缓存完成                    |
|                      | `created_at`       | `int`       | 首次缓存时间戳                     |
|                      | `last_accessed`    | `int`       | 最后访问时间戳（LRU 淘汰依据）           |
|                      | `total_chunks`     | `int`       | 总分块数                        |
| **chunk_bitmap**     | `url_hash` (PK)    | `String`    | 关联 media_index              |
|                      | `bitmap`           | `Uint8List` | 位图：每 bit 代表一个 chunk 的完成状态   |
|                      | `downloaded_bytes` | `int`       | 已下载总字节数                     |
| **playback_history** | `id` (PK)          | `int`       | 自增主键                        |
|                      | `url_hash`         | `String`    | 关联 media_index              |
|                      | `position_ms`      | `int`       | 上次播放位置（毫秒）                  |
|                      | `duration_ms`      | `int`       | 总时长                         |
|                      | `played_at`        | `int`       | 播放时间戳                       |

#### 3.1.2 响应式查询

- 使用 `tostore` 的 `watch` API 监听 `chunk_bitmap` 表变化，实时驱动 UI 进度条中的"已缓存区间"指示器。
- 使用 `watch` 监听 `media_index` 的 `is_completed` 字段，完成时触发本地播放模式切换。
- 所有 DB 写操作通过 ACID 事务保证：即使下载过程中 App 崩溃，位图与文件状态保持一致。

#### 3.1.3 LRU 缓存淘汰

- 可配置最大缓存容量（默认 2GB）。
- 淘汰策略：按 `last_accessed` 升序排列，从最旧的开始删除，直到剩余空间 ≥ 新资源预估大小。
- 淘汰时同步删除本地文件 + 清除 `media_index` 和 `chunk_bitmap` 记录。

---

### 3.2 下载 Isolate 池 — 多线程核心

#### 3.2.1 设计原则

| 原则                | 做法                                                                                 |
|-------------------|------------------------------------------------------------------------------------|
| **Isolate 数量自适应** | 移动端 2 个 Worker；桌面端 4 个 Worker；Web 端 0 个（不使用 Isolate）                               |
| **长生命周期 Isolate** | 启动时创建，App 退出时销毁，避免频繁 spawn 开销                                                      |
| **消息传递最小化**       | 仅传递 `DownloadTask`（url、chunkIndex、byteRange）和 `DownloadResult`（status、bytes），不传大数据 |
| **任务取消**          | 每个 Worker 持有 `CancelToken`（dio），主线程可随时发送 cancel 信号                                 |

#### 3.2.2 线程池工作流

```
主 Isolate (UI + Proxy)                  Worker Isolate-1         Worker Isolate-2
         │                                      │                        │
         │──── DownloadTask(chunk=5) ──────────►│                        │
         │──── DownloadTask(chunk=6) ───────────────────────────────────►│
         │                                      │                        │
         │◄─── ChunkReady(chunk=5, path) ───────│                        │
         │     → 更新 tostore bitmap            │                        │
         │     → 通知 ProxyServer 可用           │                        │
         │                                      │                        │
         │◄─── ChunkReady(chunk=6, path) ────────────────────────────────│
         │                                      │                        │
         │──── CancelTask(chunk=5) ────────────►│                        │
         │     (用户 Seek 到远处)                │──► dio.cancel()        │
         │──── DownloadTask(chunk=99) ─────────►│                        │
```

#### 3.2.3 分块策略

| 参数                    | 值                | 说明                    |
|-----------------------|------------------|-----------------------|
| `CHUNK_SIZE`          | **2 MB**         | 单个分块大小（平衡粒度与开销）       |
| `PREFETCH_COUNT`      | **3**            | 从当前播放位置向后预取 3 个 chunk |
| `PRIORITY_WINDOW`     | **当前 chunk ± 1** | 最高优先级，保证播放连续          |
| `BACKGROUND_STRATEGY` | **顺序填充**         | 空闲时从头到尾填满未下载块         |

#### 3.2.4 优先级调度

```
优先级队列:
  P0 (紧急)   — 当前播放位置所在的 chunk（正在被 Proxy 请求的）
  P1 (高)     — 当前位置后 PREFETCH_COUNT 个 chunk
  P2 (中)     — Seek 预测区域（基于用户 Seek 历史的简单线性预测）
  P3 (低)     — 顺序背景填充
```

- 当用户 Seek 时：
    1. 计算新位置对应的 chunk index。
    2. 取消所有非 P0 的进行中任务。
    3. 将新位置的 chunk 提升为 P0，重新入队。

---

### 3.3 本地代理服务器 — `shelf`

#### 3.3.1 启动策略

| 平台              | 策略                                         |
|-----------------|--------------------------------------------|
| **Native（5 端）** | App 启动时在 `127.0.0.1:0`（随机端口）启动 shelf 服务    |
| **Web**         | 不启动代理；直接使用 Service Worker + Cache API 方案替代 |

#### 3.3.2 请求处理流程

```
media_kit 发起请求:
GET http://127.0.0.1:{port}/stream?url={encoded_url}
Range: bytes=4194304-6291455

                     ┌──────────────────────┐
                     │   ProxyCacheServer    │
                     └──────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │  1. 解析 url & Range   │
                    └───────────┬───────────┘
                                │
                    ┌───────────▼───────────┐
                    │  2. 计算 chunk 范围    │
                    │  start_chunk = 2       │
                    │  end_chunk = 2         │
                    └───────────┬───────────┘
                                │
               ┌────────────────┼────────────────┐
               │                │                │
      ┌────────▼──────┐  ┌─────▼──────┐  ┌──────▼────────┐
      │ chunk 在位图中 │  │ chunk 正在  │  │ chunk 未下载   │
      │ 标记已完成？   │  │ 下载中？    │  │               │
      │ → 直接读文件   │  │ → 等待流    │  │ → 提交 P0 任务 │
      │   返回 206     │  │   合并返回  │  │   等待流返回   │
      └───────────────┘  └────────────┘  └───────────────┘
```

#### 3.3.3 流"一分二"机制

当 chunk 需要从网络下载并同时返回给播放器时：

1. Worker Isolate 通过 dio 拉取字节流。
2. 字节流通过 `SendPort` 分片发送回主 Isolate（每 64KB 一个消息）。
3. 主 Isolate 的 `StreamSplitter` 将数据同时：
    - **推入** `StreamController` → shelf Response body → media_kit 播放。
    - **写入** 本地文件 `RandomAccessFile` → 对应 chunk 的偏移位置。
4. chunk 下载完成后，更新 tostore 位图。

#### 3.3.4 HTTP 响应头

```http
HTTP/1.1 206 Partial Content
Content-Type: video/mp4          ← 根据 mime_detector 动态设置
Content-Range: bytes 4194304-6291455/104857600
Accept-Ranges: bytes
Content-Length: 2097152
Connection: keep-alive
X-Cache-Status: HIT | MISS | PARTIAL   ← 自定义头，便于调试
```

---

### 3.4 播放控制层 — 原生播放引擎

#### 3.4.1 NativePlayerController（MethodChannel + EventChannel 统一抽象）

```dart
/// Dart 侧原生播放器控制器，通过平台通道与各平台原生播放器通信。
/// 所有平台共享同一套通道协议，原生侧各自实现。
class NativePlayerController {
  static const _methodChannel = MethodChannel('flutter_cache_video_player/player');
  static const _eventChannel = EventChannel('flutter_cache_video_player/player/events');

  int? _textureId;
  int? get textureId => _textureId;

  /// 创建原生播放器实例，返回 Flutter Texture ID
  Future<int> create() async {
    _textureId = await _methodChannel.invokeMethod<int>('create');
    return _textureId!;
  }

  /// 打开媒体 URL（原生端走代理 URL，Web 端走原始 URL）
  Future<void> open(String url) => _methodChannel.invokeMethod('open', {'url': url});

  /// 控制方法
  Future<void> play()  => _methodChannel.invokeMethod('play');
  Future<void> pause() => _methodChannel.invokeMethod('pause');
  Future<void> seek(int positionMs) => _methodChannel.invokeMethod('seek', {'position': positionMs});
  Future<void> setVolume(double volume) => _methodChannel.invokeMethod('setVolume', {'volume': volume});
  Future<void> setSpeed(double speed)   => _methodChannel.invokeMethod('setSpeed',  {'speed': speed});
  Future<void> dispose() => _methodChannel.invokeMethod('dispose');

  /// 事件流：位置、时长、缓冲、播放状态、错误、播放完成
  Stream<Map<String, dynamic>> get events =>
      _eventChannel.receiveBroadcastStream().map((e) => Map<String, dynamic>.from(e as Map));
}
```

#### 3.4.2 各平台原生实现

| 平台        | 原生类                      | 核心方法                                                | 渲染管线                                        |
|-----------|--------------------------|-----------------------------------------------------|--------------------------------------------|
| **Android** | `NativeVideoPlayer.kt`    | ExoPlayer.Builder → setMediaItem → prepare → play   | SurfaceTexture → TextureRegistry.createSurfaceTexture |
| **iOS**     | `NativeVideoPlayer.swift` | AVPlayer(url:) → play() → addPeriodicTimeObserver    | AVPlayerItemVideoOutput → CVPixelBuffer → FlutterTexture |
| **macOS**   | `NativeVideoPlayer.swift` | 同 iOS（AVFoundation API 100% 共享）                     | 同 iOS                                      |
| **Windows** | `native_video_player.cpp` | IMFMediaEngine → SetSource → Play                   | ID3D11Texture2D → FlutterDesktopPixelBuffer |
| **Linux**   | `native_video_player.cc`  | gst_element_factory_make("playbin3") → set uri → PLAYING | appsink → GL texture → FlTextureGL          |
| **Web**     | `NativePlayerController`  | HTMLVideoElement → src = url → play()                | HtmlElementView (platformViewRegistry)      |

#### 3.4.3 平台工厂（保留）

```
PlatformPlayerFactory.createMediaUrl(url)
  │
  ├─ kIsWeb == true
  │   └─ 返回 originalUrl  // 直接用原始 URL
  │
  └─ kIsWeb == false
      └─ 返回 proxyUrl     // 使用本地代理 URL
```

#### 3.4.4 播放器生命周期

| 阶段       | 动作                                                                           |
|----------|------------------------------------------------------------------------------|
| **初始化**  | `NativePlayerController.create()` → 原生侧创建播放器 + 注册纹理 → 返回 textureId      |
| **打开资源** | `controller.open(proxyUrl)` → 原生播放器加载 URL → 触发代理首次请求 → 启动下载流              |
| **播放中**  | EventChannel 持续推送 position → 计算当前 chunk → 动态调整预取优先级                       |
| **Seek** | `controller.seek(ms)` → 原生播放器跳转 → EventChannel 推送新 position → 重调度下载        |
| **切换资源** | `controller.open(newUrl)` → 保存旧资源播放位置到 `playback_history` → 重置调度           |
| **销毁**   | `controller.dispose()` → 原生侧释放播放器 + 注销纹理 → 保存播放位置 → 停止预取                 |

#### 3.4.5 UI 渲染

| 类型     | 差异                                                                      |
|--------|-------------------------------------------------------------------------|
| **视频** | `Texture(textureId: controller.textureId!)` 直接渲染原生纹理                    |
| **音频** | 不渲染 Texture，使用 `AudioPlayerWidget`（封面图 + 进度条）                          |
| **Web** | `HtmlElementView(viewType: 'video-player-$id')` 嵌入 HTML5 `<video>` 元素 |
| **检测** | 根据 `mime_type`（来自 HEAD 请求或 URL 后缀）自动选择 UI                              |

#### 3.4.6 预加载（Playlist 场景）

- 播放列表下一首的前 3 个 chunk 以 P3 优先级预加载。
- 仅在 Wi-Fi 环境下启用预加载（通过 `connectivity_plus` 检测）。
- 可在设置面板中关闭。

---

### 3.5 响应式 UI 层 — `breakpoint`

#### 3.5.1 断点定义

| 断点名称      | 宽度范围          | 设备类型 | 布局策略                  |
|-----------|---------------|------|-----------------------|
| `handset` | 0 – 599 px    | 手机   | 单栏、全屏播放器、底部控制栏        |
| `tablet`  | 600 – 1023 px | 平板   | 播放器 + 右侧播放列表（可折叠）     |
| `desktop` | ≥ 1024 px     | 桌面   | 三栏：侧边栏导航 + 播放器 + 播放列表 |

#### 3.5.2 AdaptiveScaffold 逻辑

```
BreakpointBuilder(
  builder: (context, breakpoint) {
    switch (breakpoint.window) {
      case <= WindowSize.xsmall:
      case <= WindowSize.small:
        → MobileLayout()
      case <= WindowSize.medium:
        → TabletLayout()
      default:
        → DesktopLayout()
    }
  }
)
```

#### 3.5.3 主题系统

| 特性      | 实现                                              |
|---------|-------------------------------------------------|
| 浅色/深色切换 | `ThemeController` 使用 `ValueNotifier<ThemeMode>` |
| 跟随系统    | 默认 `ThemeMode.system`，用户可手动覆盖                   |
| 持久化     | 主题偏好存储在 tostore `settings` 表中                   |
| 播放器皮肤   | 视频控制栏颜色跟随当前主题                                   |

---

## 四、6 端平台适配细节

### 4.1 平台差异矩阵

| 特性           | Android                          | iOS                              | Windows                            | macOS                              | Linux                              | Web                   |
|--------------|----------------------------------|----------------------------------|------------------------------------|------------------------------------|------------------------------------|-----------------------|
| 本地代理         | ✅ shelf                          | ✅ shelf                          | ✅ shelf                            | ✅ shelf                            | ✅ shelf                            | ❌ 直接 URL             |
| Isolate 下载池  | ✅ 2 Worker                       | ✅ 2 Worker                       | ✅ 4 Worker                         | ✅ 4 Worker                         | ✅ 4 Worker                         | ❌ Web Worker          |
| 缓存路径         | `getApplicationCacheDirectory()` | `getApplicationCacheDirectory()` | `getApplicationSupportDirectory()` | `getApplicationSupportDirectory()` | `getApplicationSupportDirectory()` | IndexedDB / Cache API |
| **原生播放引擎**   | ExoPlayer (Media3)               | AVPlayer (AVFoundation)          | Media Foundation (IMFMediaEngine)  | AVPlayer (AVFoundation)            | GStreamer (playbin3)               | HTML5 `<video>`       |
| **渲染方式**     | TextureRegistry + SurfaceTexture | FlutterTexture + CVPixelBuffer   | TextureRegistry + D3D11            | FlutterTexture + CVPixelBuffer     | TextureRegistry + GL texture       | HtmlElementView       |
| **外部依赖**     | 无（Media3 通过 Gradle 引入）       | 无（系统自带 AVFoundation）          | 无（系统自带 Media Foundation）        | 无（系统自带 AVFoundation）            | 系统 GStreamer（libgstreamer1.0-dev）| 无                    |
| 后台下载         | ✅ `flutter_background_service`   | ⚠️ 受限（BGTaskScheduler）           | ✅ 原生支持                             | ✅ 原生支持                             | ✅ 原生支持                             | ❌ 页面关闭即停              |
| 网络检测         | ✅ `connectivity_plus`            | ✅ `connectivity_plus`            | ✅ `connectivity_plus`              | ✅ `connectivity_plus`              | ✅ `connectivity_plus`              | ✅ `navigator.onLine`  |

### 4.2 Web 端降级方案

由于 Web 不支持 Dart Isolate 和本地文件系统：

| 组件    | Native 方案              | Web 替代方案                                     |
|-------|------------------------|----------------------------------------------|
| 本地代理  | `shelf` 本地服务器          | 不使用，直接传 URL 给 HTML5 `<video>`                |
| 多线程下载 | Dart Isolate 池         | 不使用（浏览器自身并行请求）                               |
| 缓存存储  | 文件系统 + tostore         | `Cache API` + `IndexedDB`（tostore 的 Web 适配层） |
| 缓存指示  | 从位图实时读取                | 从 `Cache API` 查询已缓存的 Range                   |
| 播放引擎  | 原生播放器 (ExoPlayer/AVPlayer 等) | HTML5 `<video>` + HtmlElementView            |

### 4.3 桌面端打包注意事项

| 平台          | 关键配置                                                                      |
|-------------|-----------------------------------------------------------------------------|
| **Windows** | Media Foundation 系统自带，无需额外 DLL；确保 MSVC 运行时已安装                            |
| **macOS**   | AVFoundation 系统自带；签名时无需额外 dylib entitlements                              |
| **Linux**   | 需安装 GStreamer：`sudo apt install libgstreamer1.0-dev gstreamer1.0-plugins-good` |

---

## 五、关键流程时序

### 5.1 首次播放一个新视频

```
时间 ──────────────────────────────────────────────────────────►

用户点击播放
  │
  ├─① PlayerService.open(url)
  │   ├─ url_hasher 计算 hash
  │   ├─ CacheRepository.find(hash) → null（首次）
  │   ├─ HEAD 请求获取 Content-Length + Content-Type
  │   ├─ 计算 totalChunks = ceil(totalBytes / CHUNK_SIZE)
  │   ├─ tostore 事务: 创建 media_index + 初始化空 chunk_bitmap
  │   └─ PlatformPlayerFactory.createMediaUrl(proxyUrl)
  │
  ├─② NativePlayerController.open(proxyUrl)
  │   └─ 原生播放器发起首个 GET 请求
  │       ├─ ProxyCacheServer 收到 Range: bytes=0-
  │       ├─ chunk 0 未下载 → 提交 P0 任务到 DownloadWorkerPool
  │       ├─ 同时提交 chunk 1, 2, 3 为 P1 预取任务
  │       └─ StreamSplitter 等待 Worker 返回首批字节
  │
  ├─③ Worker-1 开始下载 chunk 0
  │   ├─ dio GET + Range: bytes=0-2097151
  │   ├─ 每 64KB 通过 SendPort 发回主 Isolate
  │   ├─ 主 Isolate: StreamSplitter → shelf Response + 写文件
  │   └─ chunk 0 完成 → tostore 更新 bitmap bit[0] = 1
  │
  ├─④ 原生播放器收到首批数据 → Texture 渲染首帧 🎬
  │   └─ Flutter Texture(textureId) 显示视频画面
  │
  ├─⑤ Worker-1 继续 chunk 1, Worker-2 开始 chunk 2（并行）
  │   └─ 背景持续填充...
  │
  └─⑥ 用户关闭/切换
      ├─ 保存 position_ms 到 playback_history
      ├─ 取消所有 P1-P3 任务
      └─ P3 背景填充可选继续
```

### 5.2 Seek 到未缓存位置

```
时间 ──────────────────────────────────────────────────────────►

用户拖动进度条到 60%
  │
  ├─① NativePlayerController.seek(positionMs)
  │   └─ 原生播放器跳转 → EventChannel 推送新 position
  │       └─ DownloadManager.onSeek(newByteOffset)
  │
  ├─② 计算目标 chunkIndex = floor(newByteOffset / CHUNK_SIZE)
  │   ├─ 检查 bitmap: bit[chunkIndex] == 1?
  │   │   ├─ YES → ProxyCacheServer 直接从本地文件读取，秒级响应
  │   │   └─ NO  → 继续 ③
  │   └─ 取消当前所有 P1/P2/P3 进行中的 Worker 任务
  │       (通过 CancelToken 立即中止 dio 连接)
  │
  ├─③ 提交新任务:
  │   ├─ P0: chunkIndex (目标 chunk)
  │   ├─ P1: chunkIndex+1, +2, +3 (预取)
  │   └─ P3: 继续之前未完成的背景填充
  │
  ├─④ Worker 启动新 chunk 下载
  │   └─ StreamSplitter 开始推送给 ProxyCacheServer
  │
  └─⑤ 原生播放器收到新数据，从新位置恢复播放 ▶️
      └─ Texture 渲染更新帧
```

### 5.3 再次播放已缓存视频

```
时间 ──────────────────────────────────────────────────────────►

用户点击已缓存视频
  │
  ├─① CacheRepository.find(hash) → media_index.is_completed == true
  │
  ├─② 更新 last_accessed 时间戳
  │
  ├─③ 查询 playback_history → 上次位置 position_ms
  │
  ├─④ ProxyCacheServer 所有请求命中本地文件
  │   └─ 响应头: X-Cache-Status: HIT
  │
  ├─⑤ NativePlayerController.open(proxyUrl) → seek(positionMs) → play()
  │   └─ 原生播放器从本地代理读取 → 全程零网络请求 🚀
  │       └─ Texture 渲染画面
  │
  └─⑥ 无需启动任何下载 Worker
```

---

## 六、多线程安全与并发控制

### 6.1 临界资源与锁策略

| 临界资源                     | 并发场景                    | 保护机制                                                              |
|--------------------------|-------------------------|-------------------------------------------------------------------|
| **chunk 文件写入**           | 多个 Worker 可能被分配相邻 chunk | 每个 chunk 有独立文件 `chunk_{index}.bin`，写入完成后原子 rename，无文件锁竞争          |
| **tostore bitmap 更新**    | Worker 完成回调并发触发更新       | 使用 tostore ACID 事务 + 乐观锁：读取 bitmap → 设置 bit → 带版本号写回              |
| **ProxyCacheServer 状态**  | 多个并发 Range 请求           | 每个请求独立 StreamController，共享只读 bitmap 查询                            |
| **DownloadManager 任务队列** | Seek 取消 + 新任务同时发生       | 主 Isolate 单线程执行调度逻辑，无需额外锁；通过 message passing 与 Worker 通信          |
| **文件合并**                 | 所有 chunk 下载完成后合并为单文件    | ChunkMerger 在独立 Isolate 中运行：按顺序读取 chunk_0..N → 写入 data.bin → 删除碎片 |

### 6.2 Isolate 通信协议

```dart
// 主 Isolate → Worker 的消息类型
sealed class WorkerCommand {
  DownloadChunk(url, chunkIndex, byteStart, byteEnd, savePath)
  CancelCurrent()
  Shutdown()
}

// Worker → 主 Isolate 的消息类型
sealed class WorkerEvent {
  ChunkProgress(chunkIndex, downloadedBytes, totalBytes)
  ChunkCompleted(chunkIndex, filePath, checksum)
  ChunkFailed(chunkIndex, errorMessage, retryable)
  WorkerReady()
}
```

### 6.3 错误恢复

| 错误类型                                 | 处理策略                                                                      |
|--------------------------------------|---------------------------------------------------------------------------|
| **网络中断**                             | Worker 上报 `ChunkFailed(retryable: true)` → DownloadManager 指数退避重试（最多 3 次） |
| **磁盘空间不足**                           | 写入前检查可用空间；不足时触发 LRU 淘汰；仍不足则暂停下载并通知 UI                                     |
| **App 崩溃恢复**                         | 启动时扫描本地 chunk 文件 → 与 tostore bitmap 对比 → 修正不一致状态                          |
| **Worker Isolate 异常退出**              | `Isolate.addErrorListener()` 捕获 → 重新 spawn 新 Worker → 重新分配未完成任务           |
| **HTTP 416 (Range Not Satisfiable)** | 表示服务器不支持 Range → 降级为全量下载模式，chunk 策略变为单块                                   |
| **校验失败**                             | chunk 下载完成后 MD5 校验（可选）→ 失败则删除并重下                                          |

---

## 七、性能优化策略

### 7.1 内存管理

| 策略              | 说明                                                     |
|-----------------|--------------------------------------------------------|
| **流式传输**        | 绝不将整个 chunk (2MB) 加载到内存；所有数据通过 Stream<List<int>> 流式处理  |
| **SendPort 分片** | Worker 每 64KB 发一次消息给主 Isolate，避免大消息阻塞                  |
| **缓冲区上限**       | StreamSplitter 设置 highWaterMark = 256KB，背压控制           |
| **及时释放**        | 切换视频时 dispose 旧 StreamController + 关闭 RandomAccessFile |

### 7.2 I/O 优化

| 策略               | 说明                                             |
|------------------|------------------------------------------------|
| **独立 chunk 文件**  | 避免随机写入大文件；每个 chunk 顺序写入独立小文件                   |
| **延迟合并**         | 所有 chunk 完成后，在空闲时合并为单个 `data.bin`，减少播放时的文件句柄开销 |
| **mmap 读取（桌面端）** | 合并后的大文件使用 memory-mapped file 读取，减少 syscall     |
| **批量 bitmap 更新** | 连续完成多个 chunk 时，单次事务批量更新 bitmap，减少 DB I/O       |

### 7.3 网络优化

| 策略               | 说明                                                |
|------------------|---------------------------------------------------|
| **连接复用**         | dio 配置 `persistentConnection: true`，同一域名复用 TCP 连接 |
| **并发限制**         | `dio` 的 `Interceptor` 控制同域最大并发为 4（避免服务端限流）        |
| **自适应 chunk 大小** | 监测网速：< 1 Mbps 时 chunk 降为 512KB；> 10 Mbps 时升为 4MB  |
| **CDN 友好**       | Range 请求天然对 CDN 友好，无需额外配置                         |

---

## 八、配置项与默认值

```dart
/// 所有可调参数集中定义
class CacheConfig {
  /// 单个 chunk 大小（字节），默认 2MB
  final int chunkSize;                    // 2 * 1024 * 1024

  /// 最大缓存容量（字节），默认 2GB
  final int maxCacheBytes;                // 2 * 1024 * 1024 * 1024

  /// 移动端 Worker Isolate 数量
  final int mobileWorkerCount;            // 2

  /// 桌面端 Worker Isolate 数量
  final int desktopWorkerCount;           // 4

  /// 播放时向前预取 chunk 数
  final int prefetchCount;                // 3

  /// 下载失败最大重试次数
  final int maxRetryCount;                // 3

  /// 重试退避基础延迟（毫秒）
  final int retryBaseDelayMs;             // 1000

  /// Worker → 主 Isolate 消息分片大小（字节）
  final int messageChunkSize;             // 64 * 1024

  /// StreamSplitter 背压上限（字节）
  final int highWaterMark;                // 256 * 1024

  /// 仅 Wi-Fi 下载（移动端默认 true）
  final bool wifiOnlyDownload;            // true

  /// 是否启用播放列表预加载
  final bool enablePlaylistPrefetch;      // true

  /// chunk 完成后是否校验 MD5
  final bool enableChunkChecksum;         // false (性能优先)

  /// 低网速 chunk 阈值（bytes/s），低于此值降低 chunk 大小
  final int lowSpeedThreshold;            // 128 * 1024  (128 KB/s)

  /// 高网速 chunk 阈值（bytes/s），高于此值增大 chunk 大小
  final int highSpeedThreshold;           // 1280 * 1024 (1.25 MB/s)
}
```

---

## 九、测试计划

### 9.1 单元测试

| 模块              | 测试重点                         |
|-----------------|------------------------------|
| `url_hasher`    | 相同 URL 产生相同 hash；不同 URL 无碰撞  |
| `chunk_bitmap`  | bit 读写正确；边界 chunk 索引处理       |
| `range_handler` | 解析各种 Range 格式；无 Range 头返回完整流 |
| `download_task` | 序列化/反序列化消息正确性                |
| `CacheConfig`   | 默认值验证；自适应 chunk 大小计算         |

### 9.2 集成测试

| 场景            | 验证点                  |
|---------------|----------------------|
| 全新视频播放        | 首帧延迟 < 2s（4G 网络）     |
| Seek 到未缓存区    | 新数据返回延迟 < 1.5s       |
| 完全缓存后播放       | 零网络请求；启动 < 500ms     |
| App 杀掉后恢复     | bitmap 与文件一致；可断点续传   |
| 并发 Seek（快速拖动） | 无文件写入冲突；旧任务及时取消      |
| 缓存满淘汰         | LRU 正确删除最旧资源         |
| 弱网 / 断网       | 重试机制生效；UI 显示离线提示     |
| 音频文件播放        | MIME 识别正确；UI 切换到音频模式 |

### 9.3 平台测试

| 平台      | 重点关注                                                  |
|---------|-------------------------------------------------------|
| Android | ExoPlayer 硬件解码验证；SurfaceTexture 生命周期；后台下载持续性          |
| iOS     | AVPlayer 内存管理；FlutterTexture 帧率；App 沙盒路径               |
| Windows | Media Foundation 编解码器支持；D3D11 Texture 渲染；文件路径长度       |
| macOS   | AVFoundation 权限；代码签名 + Hardened Runtime；网络权限 entitlement |
| Linux   | GStreamer 插件安装验证；GL 纹理渲染；snap/flatpak 沙盒限制            |
| Web     | HTML5 `<video>` 编解码兼容性；HtmlElementView 层叠顺序；降级播放正常    |

---

## 十、依赖清单

```yaml
dependencies:
  flutter:
    sdk: flutter

  # 数据持久层
  tostore: ^3.1.0

  # 原生播放引擎 — 无第三方依赖！各平台使用系统自带播放引擎:
  #   Android: ExoPlayer (Media3) — 通过 android/build.gradle.kts 引入
  #   iOS/macOS: AVPlayer (AVFoundation) — 系统自带，零依赖
  #   Windows: Media Foundation (IMFMediaEngine) — 系统自带，零依赖
  #   Linux: GStreamer (playbin3) — 系统 libgstreamer，CMakeLists 链接
  #   Web: HTML5 <video> — 浏览器原生，零依赖

  # 响应式 UI
  breakpoint: ^1.3.2

  # 本地代理 & 网络
  shelf: ^1.4.0
  dio: ^5.4.0

  # 工具
  path_provider: ^2.1.0   # 平台安全的缓存路径
  connectivity_plus: ^7.1.0  # 网络状态检测
  crypto: ^3.0.0           # SHA-256 哈希 & MD5 校验

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  mocktail: ^1.0.0          # Mock 测试
```

### 10.1 各平台原生依赖

| 平台        | 原生依赖                          | 引入方式                                               |
|-----------|-------------------------------|------------------------------------------------------|
| **Android** | `androidx.media3:media3-exoplayer` | `android/build.gradle.kts` 的 `dependencies` 块        |
| **iOS**     | `AVFoundation.framework`      | 系统自带，Xcode 自动链接                                    |
| **macOS**   | `AVFoundation.framework`      | 系统自带，Xcode 自动链接                                    |
| **Windows** | `mfplat.lib`, `mfuuid.lib`    | `windows/CMakeLists.txt` 的 `target_link_libraries`   |
| **Linux**   | `gstreamer-1.0`, `gstreamer-video-1.0` | `linux/CMakeLists.txt` 的 `pkg_check_modules`  |
| **Web**     | 无                             | 浏览器原生 API                                          |

---

## 十一、里程碑规划

| 阶段              | 周期      | 交付物                                           |
|-----------------|---------|-----------------------------------------------|
| **M1: 基础骨架**    | 第 1-2 周 | 目录结构搭建；tostore 表定义 & CRUD；单线程 shelf 代理可播放网络视频 |
| **M2: 多线程下载**   | 第 3-4 周 | Isolate Worker Pool；分块下载 & 位图更新；Seek 任务取消与重调度 |
| **M3: 缓存完善**    | 第 5 周   | LRU 淘汰；崩溃恢复；自适应 chunk 大小；碎片合并                 |
| **M4: UI 集成**   | 第 6 周   | breakpoint 三端布局；主题系统；缓存可视化进度条；播放列表            |
| **M5: 平台适配**    | 第 7 周   | 6 端打包验证；Web 降级方案；桌面端 libmpv 配置；iOS 后台任务       |
| **M6: 测试 & 优化** | 第 8 周   | 全量测试用例；性能 benchmark；文档完善                      |

---

## 十二、风险与规避

| 风险                        | 影响              | 规避方案                                                              |
|---------------------------|-----------------|-------------------------------------------------------------------|
| **各平台 codec 支持差异**       | 某些视频格式无法播放      | 使用各平台标准容器格式（MP4/H.264）；提供 codec 检测并给出用户提示                        |
| **FlutterTexture 帧率问题**   | 视频渲染不流畅         | 使用 `CADisplayLink`(Apple) / `Choreographer`(Android) 同步帧率        |
| **Linux GStreamer 版本碎片化** | 不同发行版表现不一致      | 支持 playbin / playbin3 自适应；最低要求 GStreamer 1.14+                   |
| Isolate 消息传递延迟            | 首帧加载变慢          | Worker 预创建 + 首个 chunk 使用同 Isolate `dio` 直传（低延迟模式）                |
| 大文件 tostore 性能            | bitmap 更新频繁导致卡顿 | bitmap 更新采用内存缓冲 + 500ms 节流写入                                     |
| CDN 不支持 Range 请求          | 分块策略失效          | HEAD 请求检测 `Accept-Ranges` 头；不支持时降级为全量下载                          |
| iOS 后台下载被系统杀死             | 下载中断            | 注册 `BGProcessingTask`；前台优先完成当前 chunk                              |
| 存储空间被系统回收（iOS）            | 缓存丢失            | 使用 `applicationSupportDirectory`（不被清理）而非 `temporaryDirectory`    |
| **Windows D3D11 设备丢失**    | 渲染中断            | 监听设备丢失事件，自动重建纹理和渲染管线                                            |
| **原生播放器内存泄漏**             | OOM 崩溃          | 严格 dispose 生命周期管理；WidgetsBindingObserver 监听 App 状态              |
