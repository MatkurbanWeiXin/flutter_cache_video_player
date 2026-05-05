# Changelog

## [1.8.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.7.0...v1.8.0) (2026-05-05)


### Features

* **proxy:** implement chunk prefetching to mitigate AVPlayer first-byte timeouts ([d5a67dc](https://github.com/Matkurban/flutter_cache_video_player/commit/d5a67dc1fedeccb60b188fbf2bdb48a1c2deaa3e))
* **video_player:** implement theme extension for customizable video player styles ([f1397a3](https://github.com/Matkurban/flutter_cache_video_player/commit/f1397a302573c33d040929ec37f4cb964576914f))

## [1.7.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.6.1...v1.7.0) (2026-05-04)


### Features

* **proxy:** enhance chunk download handling and session management ([fe6a6d9](https://github.com/Matkurban/flutter_cache_video_player/commit/fe6a6d9d486b019d3f65d1cb87166ab40a91b70f))
* **video_player:** update cached progress handling ([fe6a6d9](https://github.com/Matkurban/flutter_cache_video_player/commit/fe6a6d9d486b019d3f65d1cb87166ab40a91b70f))
* 优化初始化。 ([7376ac0](https://github.com/Matkurban/flutter_cache_video_player/commit/7376ac046f0df1041c5cbe04463c8b392f29cdcd))


### Bug Fixes

* **linux:** prevent crash on uninitialized GL texture ([fe6a6d9](https://github.com/Matkurban/flutter_cache_video_player/commit/fe6a6d9d486b019d3f65d1cb87166ab40a91b70f))
* **macos:** correct playback event reporting ([fe6a6d9](https://github.com/Matkurban/flutter_cache_video_player/commit/fe6a6d9d486b019d3f65d1cb87166ab40a91b70f))
* **player_scrubber:** clarify cached progress terminology ([fe6a6d9](https://github.com/Matkurban/flutter_cache_video_player/commit/fe6a6d9d486b019d3f65d1cb87166ab40a91b70f))
* 修复Linux中运行失败的错误 ([7376ac0](https://github.com/Matkurban/flutter_cache_video_player/commit/7376ac046f0df1041c5cbe04463c8b392f29cdcd))

## [1.6.1](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.6.0...v1.6.1) (2026-04-21)


### Bug Fixes

* format code ([c6fa4e9](https://github.com/Matkurban/flutter_cache_video_player/commit/c6fa4e9dcbbfe9cd0331aec06321f9d64f67a7d5))
* format windows and linux code ([16d992e](https://github.com/Matkurban/flutter_cache_video_player/commit/16d992eef71784ec099196c7c317c26dcbe75123))
* format windows and linux code ([7c75794](https://github.com/Matkurban/flutter_cache_video_player/commit/7c757946afe3807bd41a177187c38bbe39cf7a40))
* windows and linux bugs ([6dfeea5](https://github.com/Matkurban/flutter_cache_video_player/commit/6dfeea518ffb75466e0f3b3dee116bdd8f8b1a5f))

## [1.6.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.5.0...v1.6.0) (2026-04-19)


### Features

* 优化示例项目，优化项目结构 ([d29cb9f](https://github.com/Matkurban/flutter_cache_video_player/commit/d29cb9f78cb74015a0942646c42f8b728e2e303f))

## [1.5.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.4.0...v1.5.0) (2026-04-18)


### Features

* Add `FlutterCacheVideoPlayer.instance.getDuration(VideoSource, {timeout})` — accurately probe total media duration on all six platforms without creating a player texture or starting playback. Network sources are routed through the built-in caching proxy so probed bytes are reused by subsequent `playNetwork` calls. Desktop (libmpv) uses the same `demuxer-lavf-probesize` / `analyzeduration` knobs as the main player so tail-moov MP4s report correctly; iOS / macOS use `AVURLAsset.loadValuesAsynchronously`; Android uses `MediaMetadataRetriever`; Web uses an offscreen `<video preload="metadata">`. Failures / timeouts / live streams return `null` instead of throwing. ([4fde81e](https://github.com/Matkurban/flutter_cache_video_player/commit/4fde81ed49fd638506d2f61cc8f344fca26a1d77))

## [1.4.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.3.0...v1.4.0) (2026-04-17)


### Features

* fix windows play bugs ([65319bb](https://github.com/Matkurban/flutter_cache_video_player/commit/65319bbaea68807d925aeaea9a6d7c7e9496d768))

## [1.3.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.2.0...v1.3.0) (2026-04-17)


### Features

* Add `playNetwork` / `playFile` / `playAsset` / `playSource` entries on the   controller for explicit per-source playback; local files and Flutter assets   bypass the caching proxy. * Add `controller.takeSnapshot()` returning the current frame as a PNG   `XFile` . 

## [1.2.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.1.0...v1.2.0) (2026-04-17)


### Features

* fix bugs ([953f134](https://github.com/Matkurban/flutter_cache_video_player/commit/953f134e9f0ee6c5420b65ec5075a40923d8bae0))

## [1.1.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.0.0...v1.1.0) (2026-04-17)


### Features

* Add default video player ([7a10716](https://github.com/Matkurban/flutter_cache_video_player/commit/7a10716481d8e7f1ab2493f5adbd3b68742eb644))

## 1.0.0

Initial release.

### Features

- **Stream-while-download** playback with chunk-based caching
- **6-platform support**: Android (ExoPlayer), iOS (AVPlayer), macOS (AVPlayer), Linux (GStreamer), Windows (Media Foundation), Web (HTML5)
- **Multi-threaded downloading** via Isolate-based worker pool (2 mobile / 4 desktop)
- **Resumable downloads** with chunk bitmap tracking
- **LRU cache eviction** with configurable max cache size (default 2 GB)
- **Local HTTP proxy server** (shelf-based) for transparent cache serving
- **Priority download queue** — seeking promotes target chunk to P0
- **Smart prefetching** of upcoming chunks and playlist items
- **Playlist manager** with shuffle, repeat, and index stream
- **Player controls**: play, pause, seek, volume, speed
- **`open()` with `resumeHistory` parameter** — optionally resume from last position (default: start from beginning)
- **Built-in UI widgets**: `VideoPlayerWidget`, `AudioPlayerWidget`, `PlaylistPanel`, `ProgressBar`, `CacheIndicator`, `SettingsSheet`
- **Responsive layouts**: mobile, tablet, and desktop adaptive scaffold
- **Theme support**: light/dark themes with `ThemeController`
- **Playback history persistence** via ToStore database
- **Configurable** via `CacheConfig` (chunk size, worker count, prefetch count, retry policy, etc.)
- **Race condition protection** in download worker pool cancel flow
- **Current media protection** from LRU eviction during active download
- **Error state UI** with retry support in `VideoPlayerWidget`
