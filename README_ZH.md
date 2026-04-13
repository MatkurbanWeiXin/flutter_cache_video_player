# flutter_cache_video_player

[English](README.md)

一个跨平台 Flutter 插件，支持**边下边播、分块缓存**的音视频播放器。媒体在播放的同时以分块方式下载并缓存到本地，通过内置 HTTP 代理服务器无缝衔接——实现流畅播放、离线支持和最小化带宽消耗。

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
| Linux   | GStreamer (playbin3)                      |
| Windows | Media Foundation (IMFMediaEngine + D3D11) |
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
│  ExoPlayer │ AVPlayer │ GStreamer │ MF │ HTML5   │
└─────────────────────────────────────────────────┘
```

## 快速开始

### 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  flutter_cache_video_player: ^0.1.0
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
<uses-permission android:name="android.permission.INTERNET" />

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

安装 GStreamer 开发库：

```bash
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
```

#### Windows

无需额外配置。Media Foundation 已包含在 Windows 中。

#### Web

无需额外配置。使用 HTML5 `<video>`。

## 使用方式

### 基本用法

```dart
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';

// 初始化
final player = FlutterCacheVideoPlayer();
await player.init();

// 设置播放列表
player.playlistManager.setPlaylist([
  const PlaylistItem(url: 'https://example.com/video1.mp4', title: '视频 1'),
  const PlaylistItem(url: 'https://example.com/video2.mp4', title: '视频 2'),
]);

// 播放
await player.playlistManager.playIndex(0);

// 释放资源
await player.dispose();
```

### 自定义配置

```dart
final player = FlutterCacheVideoPlayer(
  config: CacheConfig(
    chunkSize: 4 * 1024 * 1024,       // 4 MB 分块
    maxCacheBytes: 4 * 1024 * 1024 * 1024, // 4 GB 缓存上限
    desktopWorkerCount: 6,              // 桌面端 6 个下载线程
    prefetchCount: 5,                   // 预取 5 个块
    wifiOnlyDownload: false,            // 允许蜂窝网络下载
  ),
);
await player.init();
```

### 播放控制

```dart
final svc = player.playerService;

// 打开单个 URL（默认从头开始）
await svc.open('https://example.com/video.mp4');

// 打开并恢复历史播放位置
await svc.open('https://example.com/video.mp4', resumeHistory: true);

// 播放控制
await svc.play();
await svc.pause();
await svc.playOrPause();
await svc.seek(Duration(minutes: 1, seconds: 30));
await svc.setVolume(0.8);
await svc.setSpeed(1.5);
```

### 播放列表控制

```dart
final mgr = player.playlistManager;

await mgr.next();         // 下一曲
await mgr.previous();     // 上一曲
mgr.toggleShuffle();      // 切换随机模式
mgr.toggleRepeat();       // 切换循环模式
mgr.addItem(const PlaylistItem(url: '...', title: '新歌'));
mgr.removeAt(2);
```

### 使用内置组件

```dart
// 视频播放器（含控制栏）
VideoPlayerWidget(playerService: player.playerService)

// 音频播放器
AudioPlayerWidget(playerService: player.playerService)

// 播放列表面板
PlaylistPanel(playlistManager: player.playlistManager)

// 设置面板
SettingsSheet(themeController: player.themeController)
```

### 响应式状态

`PlayerState` 是一个 `ChangeNotifier`，包含以下属性：

```dart
final state = player.playerService.state;

state.playState;    // PlayState 枚举：idle, loading, playing, paused, stopped, error
state.position;     // Duration — 当前播放位置
state.duration;     // Duration — 媒体总时长
state.volume;       // double — 当前音量
state.speed;        // double — 当前速度
state.isBuffering;  // bool — 是否正在缓冲
state.errorMessage; // String? — 错误信息
state.currentUrl;   // String? — 当前播放 URL
state.mimeType;     // String? — MIME 类型
state.isVideo;      // bool — 是否为视频
state.isAudio;      // bool — 是否为音频
state.isPlaying;    // bool — 是否正在播放
```

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

1. **请求** — 调用 `open(url)` 时，代理服务器开始从 `http://127.0.0.1:{port}` 提供媒体
2. **下载** — 下载管理器创建分块队列，按优先级将任务分发到 Isolate 工作线程池
3. **缓存** — 每个下载完成的块保存为独立文件；Bitmap 追踪哪些块已可用
4. **服务** — 代理服务器从磁盘读取已缓存的块并流式传输给原生播放器；如果某块缺失，会等待下载完成
5. **播放** — 原生播放器（ExoPlayer/AVPlayer/GStreamer/MF/HTML5）通过 Flutter Texture 渲染画面

## 示例

查看 [example](example/) 目录获取完整示例应用，包含：

- 响应式布局（手机 / 平板 / 桌面）
- 基于 Signals 的响应式状态管理
- 错误状态展示与重试
- 播放列表（随机、循环）
- 主题切换

## 许可证

详见 [LICENSE](LICENSE)。
