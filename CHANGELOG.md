# Changelog

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
