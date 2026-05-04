# flutter_cache_video_player

[English](README.md)

一个跨平台 Flutter 插件，支持**边下边播、分块缓存**的音视频播放器。媒体在播放的同时以分块方式下载并缓存到本地，通过内置 HTTP
代理服务器无缝衔接——实现流畅播放、离线支持和最小化带宽消耗。

## 功能特性

- **边下边播** — 媒体立即开始播放，同时后台分块下载
- **分块缓存** — 媒体被分割为可配置大小的块（默认 2 MB），独立缓存
- **多线程下载** — 基于 Isolate 的工作线程池（移动端 2 线程，桌面端 4 线程）并行下载
- **断点续传** — 通过 Chunk Bitmap 追踪已下载的块，中断后自动从断点继续
- **LRU 缓存淘汰** — 缓存达到上限时自动淘汰最久未使用的媒体（默认 2 GB）
- **智能预取** — 提前预取即将播放的块及播放列表中的下一项
- **优先级队列** — 拖动进度条时，目标块以 P0 最高优先级下载
- **原生渲染** — 使用各平台原生播放引擎，通过 Flutter Texture 集成实现高性能视频渲染
- **六端支持** — Android、iOS、macOS、Linux、Windows、Web
- **内置 UI** — 开箱即用的视频/音频播放器组件、播放列表面板、响应式布局、主题支持
- **播放历史** — 保存并可选恢复每个媒体的播放位置

## 平台引擎

| 平台      | 原生引擎                                      |
|---------|-------------------------------------------|
| Android | ExoPlayer (Media3)                        |
| iOS     | AVPlayer                                  |
| macOS   | AVPlayer                                  |
| Linux   | libmpv（软件渲染）                         |
| Windows | libmpv（软件渲染）                         |
| Web     | HTML5 `<video>`                           |

## 架构概览

```
┌─────────────────────────────────────────────────┐
│                    应用层                         │
├─────────────────────────────────────────────────┤
│  FlutterCacheVideoPlayer（门面类）                │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │ 播放服务  │ │ 播放列表  │ │ 主题控制器       │ │
│  │ Player   │ │ Manager  │ │ Theme            │ │
│  └────┬─────┘ └──────────┘ └──────────────────┘ │
│       │                                          │
│  ┌────▼─────────────────┐  ┌──────────────────┐ │
│  │ 原生播放器控制器       │  │ 下载管理器       │ │
│  │ (MethodChannel)      │  │ (优先级队列)      │ │
│  └────┬─────────────────┘  └────┬─────────────┘ │
│       │                         │                │
│  ┌────▼──────────┐  ┌──────────▼──────────────┐ │
│  │ 代理服务器     │  │ 工作线程池 (Isolates)   │ │
│  │ (shelf HTTP)  │  │ ┌──┐ ┌──┐ ┌──┐ ┌──┐    │ │
│  │ 127.0.0.1:0   │  │ │W1│ │W2│ │W3│ │W4│    │ │
│  └───────────────┘  │ └──┘ └──┘ └──┘ └──┘    │ │
│                      └────────────────────────┘ │
│  ┌─────────────────────────────────────────────┐ │
│  │ 缓存仓库 (ToStore) + 分块文件               │ │
│  └─────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────┤
│  原生平台层                                      │
│  ExoPlayer │ AVPlayer │  libmpv  │ libmpv │ HTML5  │
└─────────────────────────────────────────────────┘
```

## 快速开始

### 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  flutter_cache_video_player: ^lasted
```

### 平台配置

#### Android

Android 9+ 默认禁止明文 HTTP 流量。本插件使用本地 HTTP 代理（`127.0.0.1`），需要允许本地明文流量。

1. 创建 `android/app/src/main/res/xml/network_security_config.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```

2. 在 `AndroidManifest.xml` 中引用：

```xml

<application
        android:networkSecurityConfig="@xml/network_security_config"
        ...>
```

3. 确保有网络权限：

```xml

<uses-permission android:name="android.permission.INTERNET"/>
```

#### iOS

如需从 HTTP 源加载媒体，在 `ios/Runner/Info.plist` 中添加：

```xml

<key>NSAppTransportSecurity</key>
<dict>
<key>NSAllowsLocalNetworking</key>
<true/>
</dict>
```

#### macOS

在 `macos/Runner/Release.entitlements` 和 `DebugProfile.entitlements` 中添加：

```xml

<key>com.apple.security.network.client</key>
<true/>
```

在 `macos/Runner/Info.plist` 中添加：

```xml

<key>NSAppTransportSecurity</key>
<dict>
<key>NSAllowsLocalNetworking</key>
<true/>
</dict>
```

#### Linux

安装 libmpv 开发库：

```bash
# Debian / Ubuntu
sudo apt install libmpv-dev
# Fedora
sudo dnf install mpv-libs-devel
# Arch
sudo pacman -S mpv
```

#### Windows

Windows 端基于 libmpv 软件渲染实现。**无需手动安装任何东西** —— 第一次
执行 `flutter run windows` / `flutter build windows` 时，插件会自动从
[shinchiro/mpv-winbuild-cmake](https://github.com/shinchiro/mpv-winbuild-cmake)
下载一个已钉版的预编译 libmpv SDK，解压到插件下的
`windows/mpv-dev/` 并缓存复用；下载文件会按钉住的 SHA-256 校验。
`libmpv-2.dll` 会自动随 Flutter 产物一同拷贝到输出目录。

如需使用本机已有的 SDK（例如离线环境或其它架构），请通过以下方式指向：

```bash
# 推荐：目录需包含 include/mpv/*.h、libmpv.dll.a、libmpv-2.dll
cmake -DMPV_DIR=C:/libs/mpv-dev ...
# 或使用环境变量
set MPV_DIR=C:\libs\mpv-dev
```

如需切换到其它归档：

```bash
cmake -DMPV_DOWNLOAD_URL=https://example.com/mpv-dev.7z ^
      -DMPV_DOWNLOAD_SHA256=<sha256> ...
```

解压使用的是 CMake 自带的 `cmake -E tar`（libarchive），原生支持 7z。

## 配置参考

| 参数                       | 默认值   | 说明              |
|--------------------------|-------|-----------------|
| `chunkSize`              | 2 MB  | 每个下载分块的大小       |
| `maxCacheBytes`          | 2 GB  | 最大缓存总容量         |
| `mobileWorkerCount`      | 2     | 移动端并行下载线程数      |
| `desktopWorkerCount`     | 4     | 桌面端并行下载线程数      |
| `prefetchCount`          | 3     | 预取的分块数量         |
| `maxRetryCount`          | 3     | 下载失败最大重试次数      |
| `retryBaseDelayMs`       | 1000  | 指数退避基础延迟（毫秒）    |
| `wifiOnlyDownload`       | true  | 移动端仅在 Wi-Fi 下下载 |
| `enablePlaylistPrefetch` | true  | 是否预取播放列表下一项     |
| `enableChunkChecksum`    | false | 下载后是否校验 MD5     |

## 工作原理

1. **请求** — 调用 `playXXX(url)` 或 `openXXX(url)` 时，代理服务器开始从 `http://127.0.0.1:{port}` 提供媒体
2. **下载** — 下载管理器创建分块队列，按优先级将任务分发到 Isolate 工作线程池
3. **缓存** — 每个下载完成的块保存为独立文件；Bitmap 追踪哪些块已可用
4. **服务** — 代理服务器从磁盘读取已缓存的块并流式传输给原生播放器；如果某块缺失，会等待下载完成
5. **播放** — 原生播放器（ExoPlayer/AVPlayer/libmpv/HTML5）通过 Flutter Texture 渲染画面

## 组件 Widgets

插件内置两个可组合的组件。使用任意一个时，都需要你自行创建一个
`FlutterCacheVideoPlayerController`，并调用一次 `initialize()`，不再使用时
调用 `dispose()`。

### `FlutterCacheVideoPlayerView` — 纯视频画面

只负责渲染原生视频帧（原生平台通过 `Texture`，Web 通过 `HtmlElementView`），
并展示最基本的加载/缓冲/错误状态。控件、进度条、手势、浮层等全部由你自己实现 ——
当你需要完全自定义 UI 时使用它。

```dart
final controller = FlutterCacheVideoPlayerController();

@override
void initState() {
  super.initState();
  () async {
    await controller.initialize();
    await controller.playNetwork('https://example.com/video.mp4');
  }();
}

@override
Widget build(BuildContext context) {
  return FlutterCacheVideoPlayerView(
    controller: controller,
    aspectRatio: 16 / 9,
    backgroundColor: Colors.black,
    // 可选的自定义状态视图
    loadingBuilder: (ctx) => const CircularProgressIndicator(),
    errorBuilder: (ctx, msg) => Text(msg ?? '播放错误'),
  );
}

@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

**注意事项**

- 该组件仅响应 `controller.playState`、`isBuffering`、`errorMessage`、
  `textureId` 四个信号，不会显示播放/暂停按钮或进度条 —— 请自己实现，或
  改用下方的 `DefaultVideoPlayer`。
- 在 Web 上，底层 `<video>` 元素在加载期间也会保持挂载，避免 DOM 卸载/重
  挂载引起的闪烁。
- `aspectRatio` 只作用于视频帧本身。需要填满任意容器时，请在外层包
  `SizedBox.expand` / `Positioned.fill`，组件默认不会自动拉伸。
- 当 `playState == PlayState.error` 时视频帧会被隐藏，请在 `errorBuilder`
  里提供"重试"入口以便恢复播放。

### `DefaultVideoPlayer` — 高性能默认播放器

基于 `FlutterCacheVideoPlayerView` 之上构建的 iOS 风格开箱即用播放器。包含
顶部栏（关闭 + 更多）、中央控制区（±快进/快退 + 播放/暂停）、底部进度条
（**已播放 / 已缓存 / 未播放** 三段 + 等宽数字时间标签），点击画面可平滑
切换控件显隐，播放中自动隐藏。

**已缓存的进度由插件自身提供**（由缓存仓库中的下载位图驱动），你无需手动
传入。

```dart
final controller = FlutterCacheVideoPlayerController();

@override
void initState() {
  super.initState();
  () async {
    await controller.initialize();
    await controller.playNetwork('https://example.com/video.mp4');
  }();
}

@override
Widget build(BuildContext context) {
  return DefaultVideoPlayer(
    controller: controller,
    aspectRatio: 16 / 9,
    skipDuration: const Duration(seconds: 10),
    autoHideDelay: const Duration(seconds: 3),
    // 可选：自定义外观
    style: const DefaultVideoPlayerStyle(
      scrimIntensity: 0.55,
      enableGlassmorphism: false,
    ),
    onClose: () => Navigator.of(context).maybePop(),
    onMore: _showMoreSheet,
  );
}
```

**关键参数**

| 参数                 | 默认值                     | 说明                                                                                            |
|--------------------|-------------------------|-----------------------------------------------------------------------------------------------|
| `controller`       | —                       | 必填 `FlutterCacheVideoPlayerController`，使用前需 `initialize()`。                                   |
| `aspectRatio`      | `16 / 9`                | 当 `fill` 为 `false` 时生效。                                                                       |
| `fill`             | `false`                 | 为 `true` 时铺满父约束，忽略 `aspectRatio`（常用于全屏）。                                                      |
| `skipDuration`     | `Duration(seconds: 10)` | ±快进/快退时长，自动匹配 10/15/30/45/60/75/90 秒对应的 SF 图标。                                                |
| `autoHideDelay`    | `Duration(seconds: 3)`  | 播放时隐藏控件的延迟。设为 `Duration.zero` 可关闭自动隐藏。                                                        |
| `fadeDuration`     | `240 ms`                | 控件淡入/淡出时长。                                                                                    |
| `bufferedProgress` | `null`                  | 可选覆盖；不传时进度条自动使用 `controller.bufferedProgress`。                                                 |
| `style`            | `DefaultVideoPlayerStyle()` | 颜色、尺寸、内边距、遮罩强度、毛玻璃、进度条颜色/高度、时间文字样式。                                                          |
| `onClose` / `onMore` | `null` / `null`       | 顶部栏回调。`onClose` 默认回退到 `Navigator.maybePop`。                                                    |
| `topBarActions`    | `[]`                    | 在"更多"按钮之前插入的额外 action（画中画、投屏等）。                                                              |
| `errorBuilder` / `loadingBuilder` | `null`   | 透传给底层 `FlutterCacheVideoPlayerView`。                                                           |
| `topBarBuilder` / `centerControlsBuilder` / `bottomScrubberBuilder` | `null` | 用你自己的组件替换整个槽位，同时仍可拿到 `DefaultVideoPlayerSlotContext`。 |
| `extraOverlayBuilder` | `null`               | 在控件之上再叠加的自定义图层（字幕、弹幕、水印等）。                                                                    |

**注意事项**

- 图标使用 Cupertino SF Symbols。`skipDuration` 必须是 10 / 15 / 30 / 45 /
  60 / 75 / 90 秒之一才有对应图标，其他数值回退到 10 秒图标。
- 时间文字使用 `FontFeature.tabularFigures()` 保证等宽数字，避免播放时时间
  文字抖动。
- 已缓存进度**始终**来自 `controller.bufferedProgress`（除非显式传入
  `bufferedProgress`），请勿尝试从外部"推送"缓存进度，这由插件负责。
- 自动隐藏绑定在 `controller.isPlaying` 上：暂停、加载、缓冲或错误状态下，
  控件始终保持可见。
- 当用户看完视频时，该 URL 的播放历史会被重置为 `0` —— 下次再打开同一 URL
  会从头开始，而不是停在结尾。
- 全屏/横屏：将组件放进自己的全屏路由并设置 `fill: true`，配合
  `SystemChrome.setPreferredOrientations` / `SystemChrome.setEnabledSystemUIMode`
  使用。

## 播放来源（网络 / 本地文件 / 资源）

控制器提供三个显式入口方法，以及一个通用入口。**只有网络来源** 会走缓存代理；
本地文件和 Flutter 资源会直接交给原生播放器，不走代理也不占用缓存。

```dart
// 1) 网络视频 —— 走内建 HTTP 代理和分块缓存。
await controller.playNetwork('https://example.com/video.mp4');

// 只打开，ready 后保持暂停，之后再手动播放。
await controller.openNetwork('https://example.com/video.mp4');
await controller.play();

// 2) 本地文件 —— 绝对路径或 file:// URI。不走代理，不缓存。
await controller.playFile('/absolute/path/to/movie.mp4');

// 3) Flutter 资源 —— 首次调用会把 asset 抽取到临时目录。
await controller.playAsset('assets/videos/intro.mp4');

// 4) 已持有 VideoSource 时的通用入口。
await controller.playSource(VideoSource.network('https://...'));
```

现在推荐使用成对的 API：`playNetwork/openNetwork`、`playFile/openFile`、`playAsset/openAsset`、`playSource/openSource`。

使用 `playAsset` 时需要在应用的 `pubspec.yaml` 中声明资源：

```yaml
flutter:
  assets:
    - assets/videos/intro.mp4
```

## 截图与封面候选

### `takeSnapshot()` —— 截取当前画面

返回一个 PNG 的 [`XFile`]。原生平台下 `XFile.path` 是磁盘路径；Web 下是
`blob:` / `data:` URL，可直接喂给 `Image.network`。

```dart
final XFile png = await controller.takeSnapshot();
// 原生：File(png.path)
// Web ：Image.network(png.path)
```

### `extractCoverCandidates()` —— 选出若干非黑封面帧

跳过视频的首尾各 5%，从中间 90% 的时间轴上均匀采样 `count * 3` 帧，对每帧
做下采样后按 Rec.601 计算亮度，过滤掉亮度 < `minBrightness` 的帧，最后按亮度
**降序** 返回前 `count` 帧。

```dart
final frames = await FlutterCacheVideoPlayer.extractCoverCandidates(
  VideoSource.network('https://example.com/video.mp4'),
  count: 5,          // 最多返回 5 个
  minBrightness: 0.08,
);

for (final f in frames) {
  print('${f.position} → ${f.image.path} (亮度=${f.brightness})');
}
```

`VideoSource.file(...)` / `VideoSource.asset(...)` 同样支持。

### 平台实现情况

| 平台 | `takeSnapshot` | `extractCoverCandidates` |
|------|:--------------:|:------------------------:|
| iOS      | ✅ AVPlayerItemVideoOutput + Core Image | ✅ AVAssetImageGenerator |
| Android  | ✅ MediaMetadataRetriever | ✅ MediaMetadataRetriever |
| macOS    | ✅ AVPlayerItemVideoOutput + Core Image | ✅ AVAssetImageGenerator |
| Web      | ✅ `<canvas>.toDataURL` | ✅ 离屏 `<video>` + `<canvas>`（需 CORS） |
| Windows  | ✅ libmpv `screenshot-to-file` 返回 PNG 字节 | ✅ 基于 libmpv 的封面提取 |
| Linux    | ✅ libmpv `screenshot-to-file` 返回 PNG 字节 | ✅ 基于 libmpv 的封面提取 |

Web 端做封面抽取时需要视频源返回允许 `crossOrigin="anonymous"` 的 CORS
响应头，否则 canvas 会被标记为 tainted，方法会直接返回空列表。

## 获取视频总时长

### `FlutterCacheVideoPlayer.instance.getDuration()` —— 精确读取总时长

在**不创建播放器、不占用纹理、不启动播放**的前提下，精确读取任意
[`VideoSource`] 的总时长。适合做视频列表 / 封面页 / 预览时展示时长，或者
在真正打开全屏播放器之前做 URL 合法性校验。

```dart
final duration = await FlutterCacheVideoPlayer.instance.getDuration(
  VideoSource.network('https://example.com/video.mp4'),
  timeout: const Duration(seconds: 10),
);
if (duration != null) {
  debugPrint('总时长: ${duration.inMilliseconds} ms');
}
```

支持所有 `VideoSource` 类型：

```dart
// 网络源 —— 走本插件的缓存代理；探测过程中读到的字节会顺带进缓存，
// 之后调用 playNetwork(同一 URL) 可零重复下载。
await FlutterCacheVideoPlayer.instance.getDuration(
  VideoSource.network('https://example.com/video.mp4'),
);

// 本地文件 —— 绝对路径或 file:// URI。
await FlutterCacheVideoPlayer.instance.getDuration(
  VideoSource.file('/absolute/path/to/movie.mp4'),
);

// Flutter assets —— 首次调用会抽取到临时目录。
await FlutterCacheVideoPlayer.instance.getDuration(
  VideoSource.asset('assets/videos/intro.mp4'),
);
```

### 时长获取的平台实现

| 平台 | 后端实现 |
|------|----------|
| iOS      | `AVURLAsset.loadValuesAsynchronously(forKeys:["duration"])` |
| macOS    | `AVURLAsset.loadValuesAsynchronously(forKeys:["duration"])` |
| Android  | `MediaMetadataRetriever`（`METADATA_KEY_DURATION`）         |
| Linux    | libmpv 短命探测实例（与主播放器共用同一套 tail-moov 友好的 demuxer 参数） |
| Windows  | libmpv 短命探测实例（与主播放器共用同一套 tail-moov 友好的 demuxer 参数） |
| Web      | 离屏 `<video preload="metadata">` + `loadedmetadata` 事件 |

**注意事项**

- 失败 / 超时 / `duration` 非有限值（直播、无 `#EXT-X-ENDLIST` 的 HLS 等）
  都会返回 `null`，调用方需要自行判空。
- 只要调用过 `initialize()`，网络源就会走插件的本地代理 —— 探测过程中
  读到的字节（HTTP header + demuxer 需要读取的前若干 chunk）会直接进入
  下载缓存。
- Linux / Windows 的探测会启用 `demuxer-lavf-probesize=50 MB` 与
  `demuxer-lavf-analyzeduration=10 s`，确保 tail-moov 结构的 MP4（`moov`
  box 在文件尾部）能读到真实时长，而不是被错估成一个短值。
- Web 端需要视频源设置允许 `crossOrigin="anonymous"` 的 CORS 响应头；
  被浏览器拦截时该方法返回 `null`。
- 该方法永远不抛异常。UI 场景下建议传一个较短的 `timeout`（例如
  `Duration(seconds: 2)`）以保持响应流畅。

## 示例

查看 [example](example/) 目录获取完整示例应用，包含：

- 响应式布局（手机 / 平板 / 桌面）
- 基于 Signals 的响应式状态管理
- 错误状态展示与重试
- 播放列表（随机、循环）
- 主题切换

## 许可证

详见 [LICENSE](LICENSE)。
