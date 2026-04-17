# Changelog

## [1.1.0](https://github.com/Matkurban/flutter_cache_video_player/compare/v1.0.0...v1.1.0) (2026-04-17)


### Features

* Add default video player ([7a10716](https://github.com/Matkurban/flutter_cache_video_player/commit/7a10716481d8e7f1ab2493f5adbd3b68742eb644))

## 1.0.0 (2026-04-15)


### Features

* 优化代码结构，修复已知问题 ([5c7831e](https://github.com/MatkurbanWeiXin/flutter_cache_video_player/commit/5c7831ebbff56b1f60bd5e83d1b499a1514b93e9))
* 优化文档 ([f7ba85c](https://github.com/MatkurbanWeiXin/flutter_cache_video_player/commit/f7ba85c89d736b4806a98c2b323823deee48f426))
* 删除无用代码 ([4f12f03](https://github.com/MatkurbanWeiXin/flutter_cache_video_player/commit/4f12f031fa01d2170775301ac73147b2c6d97c7e))

## 1.1.0

- fix windows bugs

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
