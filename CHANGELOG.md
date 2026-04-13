# Changelog

## 0.1.0

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
