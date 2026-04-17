# flutter_cache_video_player

[中文文档](README_ZH.md)

A cross-platform Flutter plugin for playing audio and video with **chunk-based caching**. Media is downloaded in chunks
while playing, cached locally, and served through a built-in HTTP proxy — enabling seamless playback with offline
support and minimal bandwidth waste.

## Features

- **Stream-while-download** — media plays immediately while chunks download in the background
- **Chunk-based caching** — media is split into configurable chunks (default 2 MB) and cached individually
- **Multi-threaded downloads** — Isolate-based worker pool (2 workers on mobile, 4 on desktop) for parallel chunk
  downloading
- **Resumable downloads** — interrupted downloads pick up where they left off via chunk bitmap tracking
- **LRU cache eviction** — automatic eviction of least-recently-used media when cache limit is reached (default 2 GB)
- **Smart prefetching** — prefetches upcoming chunks and playlist items ahead of time
- **Priority queue** — seeking triggers urgent (P0) download of the target chunk
- **Native rendering** — platform-specific players with Flutter Texture integration for high-performance video rendering
- **6-platform support** — Android, iOS, macOS, Linux, Windows, and Web
- **Built-in UI** — ready-to-use video/audio player widgets, playlist panel, responsive layouts, and theme support
- **Playback history** — saves and optionally restores playback positions per media

## Platform Engines

| Platform | Native Engine                             |
|----------|-------------------------------------------|
| Android  | ExoPlayer (Media3)                        |
| iOS      | AVPlayer                                  |
| macOS    | AVPlayer                                  |
| Linux    | libmpv (software rendering)               |
| Windows  | libmpv (software rendering)               |
| Web      | HTML5 `<video>`                           |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Application                     │
├─────────────────────────────────────────────────┤
│  FlutterCacheVideoPlayer (Facade)               │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │ Player   │ │ Playlist │ │ Theme            │ │
│  │ Service  │ │ Manager  │ │ Controller       │ │
│  └────┬─────┘ └──────────┘ └──────────────────┘ │
│       │                                          │
│  ┌────▼─────────────────┐  ┌──────────────────┐ │
│  │ NativePlayerController│  │ Download Manager │ │
│  │ (MethodChannel)      │  │ (Priority Queue) │ │
│  └────┬─────────────────┘  └────┬─────────────┘ │
│       │                         │                │
│  ┌────▼──────────┐  ┌──────────▼──────────────┐ │
│  │ Proxy Server  │  │ Worker Pool (Isolates)  │ │
│  │ (shelf HTTP)  │  │ ┌──┐ ┌──┐ ┌──┐ ┌──┐    │ │
│  │ 127.0.0.1:0   │  │ │W1│ │W2│ │W3│ │W4│    │ │
│  └───────────────┘  │ └──┘ └──┘ └──┘ └──┘    │ │
│                      └────────────────────────┘ │
│  ┌─────────────────────────────────────────────┐ │
│  │ Cache Repository (ToStore) + Chunk Files    │ │
│  └─────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────┤
│  Native Platform Layer                           │
│  ExoPlayer │ AVPlayer │  libmpv  │ libmpv │ HTML5  │
└─────────────────────────────────────────────────┘
```

## Getting Started

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_cache_video_player: ^lasted
```

### Platform Setup

#### Android

Android 9+ blocks cleartext HTTP by default. The plugin uses a local HTTP proxy (`127.0.0.1`), so you must allow
localhost cleartext traffic.

1. Create `android/app/src/main/res/xml/network_security_config.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
```

2. Reference it in `AndroidManifest.xml`:

```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```

3. Ensure the INTERNET permission is present:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

#### iOS

Add to `ios/Runner/Info.plist` if loading from HTTP sources:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

#### macOS

Add to `macos/Runner/Release.entitlements` and `DebugProfile.entitlements`:

```xml

<key>com.apple.security.network.client</key>
<true/>
```

Add to `macos/Runner/Info.plist`:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsLocalNetworking</key>
  <true/>
</dict>
```

#### Linux

Install libmpv development libraries:

```bash
# Debian / Ubuntu
sudo apt install libmpv-dev
# Fedora
sudo dnf install mpv-libs-devel
# Arch
sudo pacman -S mpv
```

#### Windows

The Windows backend uses libmpv through software rendering. Download a
prebuilt libmpv SDK (for example the `mpv-dev-x86_64-*.7z` from the mpv
[releases page](https://mpv.io/installation/)) and extract it somewhere like
`C:\libs\mpv-dev`. The directory must contain `include/mpv/*.h`, a `libmpv.dll.a`
(or `mpv.lib`) import library, and the runtime `libmpv-2.dll`.

Pass the path when building:

```bash
flutter build windows --dart-define=MPV_DIR=C:\libs\mpv-dev
# or via CMake directly
cmake -DMPV_DIR=C:/libs/mpv-dev ...
```

`libmpv-2.dll` is bundled into the Flutter build output automatically.

## Configuration Reference

| Parameter                | Default | Description                             |
|--------------------------|---------|-----------------------------------------|
| `chunkSize`              | 2 MB    | Size of each download chunk             |
| `maxCacheBytes`          | 2 GB    | Maximum total cache size                |
| `mobileWorkerCount`      | 2       | Parallel download workers on mobile     |
| `desktopWorkerCount`     | 4       | Parallel download workers on desktop    |
| `prefetchCount`          | 3       | Number of chunks to prefetch ahead      |
| `maxRetryCount`          | 3       | Max retries for failed chunk downloads  |
| `retryBaseDelayMs`       | 1000    | Base delay for exponential backoff (ms) |
| `wifiOnlyDownload`       | true    | Restrict downloads to Wi-Fi on mobile   |
| `enablePlaylistPrefetch` | true    | Prefetch next playlist items            |
| `enableChunkChecksum`    | false   | Verify MD5 checksum after download      |

## How It Works

1. **Request** — When `open(url)` is called, the proxy server starts serving the media URL from
   `http://127.0.0.1:{port}`
2. **Download** — The download manager creates a chunk queue and dispatches tasks to the Isolate worker pool based on
   priority
3. **Cache** — Each downloaded chunk is saved as a separate file; a bitmap tracks which chunks are available
4. **Serve** — The proxy server reads cached chunks from disk and streams them to the native player; if a chunk is
   missing, it waits for the download to complete
5. **Play** — The native player (ExoPlayer/AVPlayer/libmpv/HTML5) renders frames via Flutter Texture

## Widgets

The plugin ships with two composable widgets. Pair either of them with a
`FlutterCacheVideoPlayerController` that you create, `initialize()` once, and
`dispose()` when done.

### `FlutterCacheVideoPlayerView` — bare video surface

Renders only the native video frame (via `Texture` on native platforms and
`HtmlElementView` on web) plus a minimal loading / buffering / error state.
Controls, progress bars, gestures and overlays are 100% your responsibility —
use this when you want a fully custom UI.

```dart
final controller = FlutterCacheVideoPlayerController();

@override
void initState() {
  super.initState();
  () async {
    await controller.initialize();
    await controller.open('https://example.com/video.mp4');
    await controller.play();
  }();
}

@override
Widget build(BuildContext context) {
  return FlutterCacheVideoPlayerView(
    controller: controller,
    aspectRatio: 16 / 9,
    backgroundColor: Colors.black,
    // Optional custom states.
    loadingBuilder: (ctx) => const CircularProgressIndicator(),
    errorBuilder: (ctx, msg) => Text(msg ?? 'Playback error'),
  );
}

@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

**Notes**

- The view only reacts to `controller.playState`, `isBuffering`, `errorMessage`
  and `textureId`. It will not show a play/pause button or scrubber — compose
  your own, or use `DefaultVideoPlayer` below.
- On the web the underlying `<video>` element is kept mounted even during
  loading to avoid DOM remount glitches.
- `aspectRatio` is applied to the video frame. To fill an arbitrary box, wrap
  the view in `SizedBox.expand` / `Positioned.fill` yourself — the widget does
  not stretch to fill by default.
- When `playState` is `PlayState.error` the frame is hidden entirely; render
  a retry affordance inside `errorBuilder` so users can recover.

### `DefaultVideoPlayer` — polished drop-in UI

An iOS-style, ready-to-use player built on top of `FlutterCacheVideoPlayerView`.
It renders the video frame plus an overlay with a top bar (close + more),
centered transport controls (±skip + play/pause), a thin bottom scrubber with
**played / buffered / unplayed** segments and monospaced time labels. Tapping
the frame fades the overlay in/out; it auto-hides during playback.

Cached progress is supplied **by the plugin itself** (driven by the download
bitmap in the cache repository) — you do not need to feed it manually.

```dart
final controller = FlutterCacheVideoPlayerController();

@override
void initState() {
  super.initState();
  () async {
    await controller.initialize();
    await controller.open('https://example.com/video.mp4');
    await controller.play();
  }();
}

@override
Widget build(BuildContext context) {
  return DefaultVideoPlayer(
    controller: controller,
    aspectRatio: 16 / 9,
    skipDuration: const Duration(seconds: 10),
    autoHideDelay: const Duration(seconds: 3),
    // Optional: customise look & feel.
    style: const DefaultVideoPlayerStyle(
      scrimIntensity: 0.55,
      enableGlassmorphism: false,
    ),
    onClose: () => Navigator.of(context).maybePop(),
    onMore: _showMoreSheet,
  );
}
```

**Key parameters**

| Parameter          | Default                   | Description                                                                                               |
|--------------------|---------------------------|-----------------------------------------------------------------------------------------------------------|
| `controller`       | —                         | Required `FlutterCacheVideoPlayerController`. Must be `initialize()`-d before playback starts.            |
| `aspectRatio`      | `16 / 9`                  | Used when `fill` is `false`.                                                                              |
| `fill`             | `false`                   | When `true` the player fills the parent constraints instead of respecting `aspectRatio` (use for fullscreen). |
| `skipDuration`     | `Duration(seconds: 10)`   | Controls the ±skip buttons. Matching SF Symbols are auto-picked for 10/15/30/45/60/75/90 s.              |
| `autoHideDelay`    | `Duration(seconds: 3)`    | Time before the overlay fades while playing. `Duration.zero` disables auto-hide.                          |
| `fadeDuration`     | `240 ms`                  | Overlay fade animation.                                                                                   |
| `bufferedProgress` | `null`                    | Optional override; by default the plugin's `controller.bufferedProgress` drives the buffered segment.     |
| `style`            | `DefaultVideoPlayerStyle()` | Colors, sizes, paddings, scrim, glass, scrubber colors/heights, time label text style.                  |
| `onClose` / `onMore` | `null` / `null`         | Top-bar callbacks. `onClose` falls back to `Navigator.maybePop`.                                          |
| `topBarActions`    | `[]`                      | Extra actions injected before the "more" button (PiP, cast, etc.).                                        |
| `errorBuilder` / `loadingBuilder` | `null`     | Forwarded to the underlying `FlutterCacheVideoPlayerView`.                                                |
| `topBarBuilder` / `centerControlsBuilder` / `bottomScrubberBuilder` | `null` | Fully replace any slot with your own widget while still receiving a `DefaultVideoPlayerSlotContext`. |
| `extraOverlayBuilder` | `null`                 | Adds an extra layer above the controls (subtitles, danmu, watermark, …).                                  |

**Notes**

- Icons are Cupertino SF Symbols. `skipDuration` must be one of 10 / 15 / 30 /
  45 / 60 / 75 / 90 s to get a matching glyph; other values fall back to the
  10 s glyph.
- Time labels use `FontFeature.tabularFigures()` to avoid horizontal jitter
  during playback.
- The buffered segment is **always** read from `controller.bufferedProgress`
  unless you pass an explicit `bufferedProgress` listenable — do not try to
  "push" cache progress into the widget, the plugin owns it.
- Auto-hide is wired to `controller.isPlaying`: the overlay stays pinned
  whenever playback is paused, loading, buffering or errored.
- When the user seeks to the end and the media completes, the stored playback
  history for that URL is reset — reopening the same URL starts from `0`.
- For landscape/fullscreen, wrap the widget in your own route and set `fill:
  true`; combine with `SystemChrome.setPreferredOrientations` /
  `SystemChrome.setEnabledSystemUIMode` as needed.

## Sources & Playback

The controller exposes three explicit entry points plus a generic one. Only
network sources are piped through the caching proxy; local files and Flutter
assets are handed directly to the native player.

```dart
// 1) Network — cached through the built-in HTTP proxy.
await controller.playNetwork('https://example.com/video.mp4');

// 2) Local file — absolute path or file:// URI. No proxy, no caching.
await controller.playFile('/absolute/path/to/movie.mp4');

// 3) Flutter asset — first call extracts the asset to the temp directory.
await controller.playAsset('assets/videos/intro.mp4');

// 4) Generic — use when you already have a VideoSource.
await controller.playSource(VideoSource.network('https://...'));
```

Legacy `controller.open(url)` is kept and is equivalent to `playNetwork(url)`.

When using `playAsset`, declare the asset under your app's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/videos/intro.mp4
```

## Snapshots & Cover Candidates

### `takeSnapshot()` — capture the current frame

Captures whatever the native player is rendering right now and returns a PNG
as an [`XFile`]. On native platforms the `XFile.path` points to a file on
disk; on web it is a `blob:` / `data:` URL.

```dart
final XFile png = await controller.takeSnapshot();
// native: File(png.path)
// web   : Image.network(png.path)
```

### `extractCoverCandidates()` — pick the best cover frames

Scans a video and returns a small, ranked list of non-black candidate frames.
The algorithm skips the first/last 5 % of the timeline, samples `count * 3`
evenly-distributed frames from the middle 90 %, computes Rec. 601 luma on a
downsampled buffer, drops frames dimmer than `minBrightness`, and returns the
top `count` frames sorted by brightness **descending**.

```dart
final frames = await FlutterCacheVideoPlayer.extractCoverCandidates(
  VideoSource.network('https://example.com/video.mp4'),
  count: 5,          // up to 5 results
  minBrightness: 0.08,
);

for (final f in frames) {
  print('${f.position} → ${f.image.path} (brightness=${f.brightness})');
}
```

Works with any `VideoSource` (`network`, `file`, `asset`).

### Platform support for snapshot / covers

| Platform | `takeSnapshot` | `extractCoverCandidates` |
|----------|:--------------:|:------------------------:|
| iOS      | ✅ AVPlayerItemVideoOutput + Core Image | ✅ AVAssetImageGenerator |
| Android  | ✅ MediaMetadataRetriever | ✅ MediaMetadataRetriever |
| macOS    | ✅ AVPlayerItemVideoOutput + Core Image | ✅ AVAssetImageGenerator |
| Web      | ✅ `<canvas>.toDataURL` | ✅ offscreen `<video>` + `<canvas>` (CORS required) |
| Windows  | ✅ PNG bytes via libmpv `screenshot-to-file` | ✅ libmpv-based extraction |
| Linux    | ✅ PNG bytes via libmpv `screenshot-to-file` | ✅ libmpv-based extraction |

On Web, cover extraction requires the video server to send CORS headers
allowing `crossOrigin="anonymous"` — otherwise the canvas is tainted and the
method returns an empty list.

## Example

See the [example](example/) directory for a complete app demonstrating:

- Responsive layout (mobile / tablet / desktop)
- Signals-based reactive state management
- Error state display with retry
- Playlist with shuffle and repeat
- Theme support

## License

See [LICENSE](LICENSE) for details.

