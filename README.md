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

| Platform | Native Engine               |
|----------|-----------------------------|
| Android  | ExoPlayer (Media3)          |
| iOS      | AVPlayer                    |
| macOS    | AVPlayer                    |
| Linux    | libmpv (software rendering) |
| Windows  | libmpv (software rendering) |
| Web      | HTML5 `<video>`             |

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

1. **Request** — When `playXXX(url)` or `openXXX(url)` is called, the proxy server starts serving the media URL from
   `http://127.0.0.1:{port}`
2. **Download** — The download manager creates a chunk queue and dispatches tasks to the Isolate worker pool based on
   priority
3. **Cache** — Each downloaded chunk is saved as a separate file; a bitmap tracks which chunks are available
4. **Serve** — The proxy server reads cached chunks from disk and streams them to the native player; if a chunk is
   missing, it waits for the download to complete
5. **Play** — The native player (ExoPlayer/AVPlayer/libmpv/HTML5) renders frames via Flutter Texture

## Widgets

The plugin ships with two composable widgets. Pair either of them with a
`VideoPlayerController` that you create, `initialize()` once, and
`dispose()` when done.

### `CorePlayer` — bare video surface

Renders only the native video frame (via `Texture` on native platforms and
`HtmlElementView` on web) plus a minimal loading / buffering / error state.
Controls, progress bars, gestures and overlays are 100% your responsibility —
use this when you want a fully custom UI.

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

### `VideoPlayer` — polished drop-in UI

An iOS-style, ready-to-use player built on top of `FlutterCacheVideoPlayerView`.
It renders the video frame plus an overlay with a top bar (close + more),
centered transport controls (±skip + play/pause), a thin bottom scrubber with
**played / buffered / unplayed** segments and monospaced time labels. Tapping
the frame fades the overlay in/out; it auto-hides during playback.

Cached progress is supplied **by the plugin itself** (driven by the download
bitmap in the cache repository) — you do not need to feed it manually.

**Key parameters**

| Parameter                                                           | Default                 | Description                                                                                                   |
|---------------------------------------------------------------------|-------------------------|---------------------------------------------------------------------------------------------------------------|
| `controller`                                                        | —                       | Required `VideoPlayerController`. Must be `initialize()`-d before playback starts.                            |
| `aspectRatio`                                                       | `16 / 9`                | Used when `fill` is `false`.                                                                                  |
| `fill`                                                              | `false`                 | When `true` the player fills the parent constraints instead of respecting `aspectRatio` (use for fullscreen). |
| `skipDuration`                                                      | `Duration(seconds: 10)` | Controls the ±skip buttons. Matching SF Symbols are auto-picked for 10/15/30/45/60/75/90 s.                   |
| `autoHideDelay`                                                     | `Duration(seconds: 3)`  | Time before the overlay fades while playing. `Duration.zero` disables auto-hide.                              |
| `fadeDuration`                                                      | `240 ms`                | Overlay fade animation.                                                                                       |
| `bufferedProgress`                                                  | `null`                  | Optional override; by default the plugin's `controller.bufferedProgress` drives the buffered segment.         |
| `style`                                                             | `VideoPlayerTheme()`    | Colors, sizes, paddings, scrim, glass, scrubber colors/heights, time label text style.                        |
| `onClose` / `onMore`                                                | `null` / `null`         | Top-bar callbacks. `onClose` falls back to `Navigator.maybePop`.                                              |
| `topBarActions`                                                     | `[]`                    | Extra actions injected before the "more" button (PiP, cast, etc.).                                            |
| `errorBuilder` / `loadingBuilder`                                   | `null`                  | Forwarded to the underlying `CorePlayer`.                                                                     |
| `topBarBuilder` / `centerControlsBuilder` / `bottomScrubberBuilder` | `null`                  | Fully replace any slot with your own widget while still receiving a `VideoPlayerSlotContext`.                 |
| `extraOverlayBuilder`                                               | `null`                  | Adds an extra layer above the controls (subtitles, danmu, watermark, …).                                      |

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

The controller exposes paired open/play entry points plus generic variants.
`play*` prepares the media and starts playback immediately. `open*` prepares
the media and leaves it paused once ready. Only network sources are piped
through the caching proxy; local files and Flutter assets are handed directly
to the native player.

```dart
// 1) Network — cached through the built-in HTTP proxy and auto-plays.
await controller.playNetwork('https://example.com/video.mp4');

// 2) Network open-only — prepare, then start later.
await controller.openNetwork('https://example.com/video.mp4');
await controller.play();

// 3) Local file — absolute path or file:// URI. No proxy, no caching.
await controller.playFile('/absolute/path/to/movie.mp4');

// 4) Flutter asset — first call extracts the asset to the temp directory.
await controller.playAsset('assets/videos/intro.mp4');

// 5) Generic — use when you already have a VideoSource.
await controller.playSource(VideoSource.network('https://...'));
```

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

final XFile png = await
controller.takeSnapshot
();
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

final frames = await
FlutterCacheVideoPlayer.instance.extractCoverCandidates
(
VideoSource.network('https://example.com/video.mp4'),
count: 5, // up to 5 results
minBrightness: 0.08,
);

for (final f in frames) {
print('${f.position} → ${f.image.path} (brightness=${f.brightness})');
}
```

Works with any `VideoSource` (`network`, `file`, `asset`).

### Platform support for snapshot / covers

| Platform |               `takeSnapshot`                |              `extractCoverCandidates`              |
|----------|:-------------------------------------------:|:--------------------------------------------------:|
| iOS      |   ✅ AVPlayerItemVideoOutput + Core Image    |              ✅ AVAssetImageGenerator               |
| Android  |          ✅ MediaMetadataRetriever           |              ✅ MediaMetadataRetriever              |
| macOS    |   ✅ AVPlayerItemVideoOutput + Core Image    |              ✅ AVAssetImageGenerator               |
| Web      |           ✅ `<canvas>.toDataURL`            | ✅ offscreen `<video>` + `<canvas>` (CORS required) |
| Windows  | ✅ PNG bytes via libmpv `screenshot-to-file` |             ✅ libmpv-based extraction              |
| Linux    | ✅ PNG bytes via libmpv `screenshot-to-file` |             ✅ libmpv-based extraction              |

On Web, cover extraction requires the video server to send CORS headers
allowing `crossOrigin="anonymous"` — otherwise the canvas is tainted and the
method returns an empty list.

## Getting Video Duration

### `FlutterCacheVideoPlayer.instance.getDuration()` — probe total duration

Accurately reads the total duration of any [`VideoSource`] **without** creating
a player, texture, or starting playback. This is the recommended way to show
durations in lists / thumbnails / previews, or to pre-validate a URL before
opening it in a full player.

```dart

final duration = await
FlutterCacheVideoPlayer.instance.getDuration
(
VideoSource.network('https://example.com/video.mp4'),
timeout: const Duration(seconds: 10),
);
if (duration != null) {
debugPrint('Total duration: ${duration.inMilliseconds} ms');
}
```

Works with any `VideoSource`:

```dart
// Network — piped through the caching proxy; bytes read while probing
// are reused by subsequent playNetwork(sameUrl) calls.
await
FlutterCacheVideoPlayer.instance.getDuration
(
VideoSource.network('https://example.com/video.mp4'),
);

// Local file — absolute path or file:// URI.
await FlutterCacheVideoPlayer.instance.getDuration(
VideoSource.file('/absolute/path/to/movie.mp4'),
);

// Flutter asset — extracted to the temp directory on first use.
await FlutterCacheVideoPlayer.instance.getDuration(
VideoSource.asset('assets/videos/intro.mp4
'
)
,
);
```

### Platform support for duration

| Platform | Backend                                                                         |
|----------|---------------------------------------------------------------------------------|
| iOS      | `AVURLAsset.loadValuesAsynchronously(forKeys:["duration"])`                     |
| macOS    | `AVURLAsset.loadValuesAsynchronously(forKeys:["duration"])`                     |
| Android  | `MediaMetadataRetriever` (`METADATA_KEY_DURATION`)                              |
| Linux    | libmpv short-lived probe (same tail-moov-safe demuxer flags as the main player) |
| Windows  | libmpv short-lived probe (same tail-moov-safe demuxer flags as the main player) |
| Web      | Offscreen `<video preload="metadata">` + `loadedmetadata`                       |

**Notes**

- Returns `null` on failure, timeout, or non-finite durations (live streams,
  HLS without a `#EXT-X-ENDLIST` marker). Callers should handle `null`.
- Network sources are routed through the plugin's proxy whenever
  `initialize()` has been called — probed bytes (HTTP headers and the first
  chunk the demuxer needs to read duration) become part of the normal download
  cache.
- On Linux / Windows the probe applies `demuxer-lavf-probesize=50 MB` and
  `demuxer-lavf-analyzeduration=10 s` so tail-moov MP4s (where the `moov`
  atom is at the end of the file) report their real duration instead of a
  truncated estimate.
- On Web the server must permit `crossOrigin="anonymous"`; on CORS failure
  the method returns `null`.
- The method never throws — pass a short `timeout` (e.g. `Duration(seconds:
  2)`) when building responsive UIs.

## Example

See the [example](example/) directory for a complete app demonstrating:

- Responsive layout (mobile / tablet / desktop)
- Signals-based reactive state management
- Error state display with retry
- Playlist with shuffle and repeat
- Theme support

## License

See [LICENSE](LICENSE) for details.

