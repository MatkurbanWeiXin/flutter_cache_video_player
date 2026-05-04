import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'native_player_controller.dart';

/// 播放控制器，封装 NativePlayerController 并管理生命周期、事件监听和历史持久化。
/// Player controller wrapping NativePlayerController with lifecycle management, event listeners, and history persistence.
class VideoPlayerController {
  final NativePlayerController _nativeController;

  final List<VoidCallback> _disposers = <VoidCallback>[];

  /// 防止旧媒体的残留事件干扰新媒体的状态。open() 时重置为 false，
  /// 收到新媒体的 playing(true) 后置为 true。
  /// Guards against stale native events from the previous media session.
  /// Reset to false on open(), set to true when playing(true) is received.
  bool _hasPlayedSinceOpen = false;

  /// 防止媒体已经 ready 但尚未开始播放时，UI 仍然停留在 loading。
  /// Tracks whether the current media session has produced a readiness signal
  /// (for example duration metadata) even if playback has not started yet.
  bool _hasReadySinceOpen = false;

  final FlutterSignal<PlayState> playState = signal(PlayState.idle);

  final FlutterSignal<Duration> position = signal(Duration.zero);

  final FlutterSignal<Duration> duration = signal(Duration.zero);

  final FlutterSignal<double> volume = signal(1.0);

  final FlutterSignal<double> speed = signal(1.0);

  final FlutterSignal<bool> isBuffering = signal(false);

  final FlutterSignal<String?> errorMessage = signal<String?>(null);

  final FlutterSignal<String?> currentUrl = signal<String?>(null);

  final FlutterSignal<String?> mimeType = signal<String?>(null);

  /// 当前媒体的缓存进度（0.0 – 1.0），由插件根据下载位图自动更新。
  /// Current media cached progress (0.0 – 1.0), auto-updated by the plugin
  /// from the download bitmap.
  final FlutterSignal<double> cachedProgress = signal<double>(0.0);

  @Deprecated('Use cachedProgress for cache/download progress.')
  FlutterSignal<double> get bufferedProgress => cachedProgress;

  /// 当前媒体已缓存字节数。
  /// Bytes downloaded for the current media.
  final FlutterSignal<int> downloadedBytes = signal<int>(0);

  /// 当前媒体是否已完整缓存。
  /// Whether the current media is fully cached.
  final FlutterSignal<bool> isFullyCached = signal<bool>(false);

  /// 视频原始分辨率（已考虑显示方向）。未知时为 `Size.zero`。
  /// Natural video size reported by the native player. `Size.zero` when
  /// the size is not yet known.
  final FlutterSignal<Size> videoSize = signal<Size>(Size.zero);

  /// 视频宽高比（width / height）。未知时返回 `null`。
  /// Video aspect ratio (width / height). Returns `null` until known.
  late final FlutterComputed<double?> videoAspectRatio = computed(() {
    final size = videoSize.value;
    if (size.width <= 0 || size.height <= 0) return null;
    return size.width / size.height;
  });

  StreamSubscription<List<Map<String, dynamic>>>? _bitmapSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _mediaIndexSubscription;
  int _currentTotalChunks = 0;

  late final FlutterComputed<bool> isVideo = computed(() {
    return mimeType.value?.startsWith('video/') ?? false;
  });

  late final FlutterComputed<bool> isAudio = computed(() {
    return mimeType.value?.startsWith('audio/') ?? false;
  });

  late final FlutterComputed<bool> isPlaying = computed(() {
    return playState.value == PlayState.playing;
  });

  late final FlutterComputed<double> progressPercent = computed(() {
    if (duration.value.inMilliseconds == 0) return 0.0;
    return position.value.inMilliseconds / duration.value.inMilliseconds;
  });

  VideoPlayerController({NativePlayerController? nativeController})
    : _nativeController = nativeController ?? NativePlayerController();

  /// 原生纹理 ID，用于 Texture widget。
  /// Native texture ID for the Texture widget.
  int? get textureId => _nativeController.textureId;

  /// 初始化原生播放器（创建纹理并设置事件监听）。
  /// Initializes the native player (creates texture and sets up event listeners).
  Future<void> initialize() async {
    await _nativeController.create();
    VoidCallback playingEffect = effect(() {
      final playing = _nativeController.playingSignal.value;
      if (playing) {
        final wasFirstPlay = !_hasPlayedSinceOpen;
        _hasPlayedSinceOpen = true;
        _markReadySinceOpen();
        if (wasFirstPlay) {
          final dur = _nativeController.durationSignal.value;
          if (dur > Duration.zero) {
            duration.value = dur;
          }
        }
        playState.value = PlayState.playing;
        return;
      }
      if (!_hasReadySinceOpen) {
        return;
      }
      if (playState.value == PlayState.stopped) {
        return;
      }
      playState.value = PlayState.paused;
    });
    VoidCallback positionEffect = effect(() {
      final value = _nativeController.positionSignal.value;
      if (!_hasReadySinceOpen) return;
      position.value = value;
    });
    VoidCallback durationEffect = effect(() {
      final value = _nativeController.durationSignal.value;
      if (value > Duration.zero && !_hasReadySinceOpen) {
        _markReadySinceOpen();
      }
      if (!_hasReadySinceOpen) return;
      duration.value = value;
    });
    VoidCallback bufferingEffect = effect(() {
      final buffering = _nativeController.bufferingSignal.value;
      if (!_hasReadySinceOpen) return;
      isBuffering.value = buffering;
    });
    VoidCallback errorEffect = effect(() {
      final error = _nativeController.errorSignal.value;
      if (error == null) return;
      errorMessage.value = error;
      playState.value = PlayState.error;
    });
    VoidCallback completedEffect = effect(() {
      _nativeController.completedSignal.value;
      if (!_hasPlayedSinceOpen) {
        return;
      }
      playState.value = PlayState.stopped;
    });
    VoidCallback videoSizeEffect = effect(() {
      final size = _nativeController.videoSizeSignal.value;
      videoSize.value = size;
      if (size.width > 0 && size.height > 0 && !_hasReadySinceOpen) {
        _markReadySinceOpen();
      }
    });
    _disposers.addAll([
      playingEffect,
      positionEffect,
      durationEffect,
      bufferingEffect,
      errorEffect,
      completedEffect,
      videoSizeEffect,
    ]);
  }

  void _markReadySinceOpen() {
    if (_hasReadySinceOpen) return;
    _hasReadySinceOpen = true;

    final nativeDuration = _nativeController.durationSignal.value;
    if (nativeDuration > Duration.zero) {
      duration.value = nativeDuration;
    }
    isBuffering.value = _nativeController.bufferingSignal.value;

    if (!_nativeController.playingSignal.value && playState.value == PlayState.loading) {
      playState.value = PlayState.paused;
    }
  }

  int _estimateByteOffset(Duration position) {
    if (duration.value.inMilliseconds == 0) return 0;
    return 0;
  }

  /// 打开并播放一个网络地址（`http(s)://...`），走插件的缓存代理。
  /// Open and start playing a network URL (`http(s)://...`) routed through
  /// the caching proxy.
  Future<void> playNetwork(String url, {bool resumeHistory = false}) {
    return _openSource(VideoSource.network(url), resumeHistory: resumeHistory, autoPlay: true);
  }

  /// 仅打开网络地址，等待调用方稍后显式触发 [play]。
  /// Open a network URL and leave it paused once ready.
  Future<void> openNetwork(String url, {bool resumeHistory = false}) {
    return _openSource(VideoSource.network(url), resumeHistory: resumeHistory, autoPlay: false);
  }

  /// 打开并播放本地文件（绝对路径或 `file://` URI）。不走代理。
  /// Open and start playing a local file (absolute path or `file://` URI).
  /// Bypasses the proxy.
  Future<void> playFile(String path, {bool resumeHistory = false}) {
    return _openSource(VideoSource.file(path), resumeHistory: resumeHistory, autoPlay: true);
  }

  /// 仅打开本地文件，等待调用方稍后显式触发 [play]。
  /// Open a local file and leave it paused once ready.
  Future<void> openFile(String path, {bool resumeHistory = false}) {
    return _openSource(VideoSource.file(path), resumeHistory: resumeHistory, autoPlay: false);
  }

  /// 打开并播放 Flutter assets 中的媒体；首次调用会抽取到临时目录。不走代理。
  /// Open and start playing a media bundled as a Flutter asset; first use
  /// extracts it to temp.
  Future<void> playAsset(String assetPath, {AssetBundle? bundle, bool resumeHistory = false}) {
    return _openSource(
      VideoSource.asset(assetPath, bundle: bundle),
      resumeHistory: resumeHistory,
      autoPlay: true,
    );
  }

  /// 仅打开 Flutter assets 中的媒体，等待调用方稍后显式触发 [play]。
  /// Open a bundled media asset and leave it paused once ready.
  Future<void> openAsset(String assetPath, {AssetBundle? bundle, bool resumeHistory = false}) {
    return _openSource(
      VideoSource.asset(assetPath, bundle: bundle),
      resumeHistory: resumeHistory,
      autoPlay: false,
    );
  }

  /// 使用 [VideoSource] 直接打开并开始播放。
  /// Open the given [VideoSource] and start playback.
  Future<void> playSource(VideoSource source, {bool resumeHistory = false}) {
    return _openSource(source, resumeHistory: resumeHistory, autoPlay: true);
  }

  /// 使用 [VideoSource] 直接打开，等待调用方稍后显式触发 [play]。
  /// Open the given [VideoSource] and leave it paused once ready.
  Future<void> openSource(VideoSource source, {bool resumeHistory = false}) {
    return _openSource(source, resumeHistory: resumeHistory, autoPlay: false);
  }

  Future<void> _openSource(
    VideoSource source, {
    required bool resumeHistory,
    required bool autoPlay,
  }) async {
    try {
      await _saveCurrentPosition();

      reset();

      final identity = source.identity;
      currentUrl.value = identity;

      final type = MimeDetector.detect(identity);
      mimeType.value = type;

      playState.value = PlayState.loading;

      final resolved = await source.resolveToNativeUrl();
      final mediaUrl = await _resolveMediaUrl(source, resolved);

      await _nativeController.open(mediaUrl);

      if (source.isNetwork) {
        if (FlutterCacheVideoPlayer.instance.isInitialized) {
          // Start watching cache progress from the plugin's cache repository.
          _subscribeCacheProgress(identity);
        } else {
          await _cancelCacheSubscriptions();
        }
      } else {
        // Local sources are "fully cached" by definition. Skip cache
        // subscriptions entirely.
        await _cancelCacheSubscriptions();
        batch(() {
          isFullyCached.value = true;
          cachedProgress.value = 1.0;
          downloadedBytes.value = _safeFileSize(resolved);
        });
      }

      if (resumeHistory && FlutterCacheVideoPlayer.instance.isInitialized) {
        final urlHash = UrlHasher.hash(identity);
        try {
          final history = await FlutterCacheVideoPlayer.instance.historyRepo.getLastPosition(
            urlHash,
          );
          if (history != null && history.positionMs > 0) {
            _nativeController.seek(history.positionMs);
          }
        } catch (_) {}
      }

      if (autoPlay) {
        await _nativeController.play();
      }
    } catch (e) {
      errorMessage.value = e.toString();
      playState.value = PlayState.error;
    }
  }

  Future<String> _resolveMediaUrl(VideoSource source, String resolvedUrl) async {
    if (!source.isNetwork) {
      return resolvedUrl;
    }

    final plugin = FlutterCacheVideoPlayer.instance;
    if (!plugin.isInitialized) {
      return resolvedUrl;
    }

    try {
      return await plugin.playerFactory.createMediaUrl(source, resolvedUrl);
    } catch (_) {
      return resolvedUrl;
    }
  }

  int _safeFileSize(String resolvedUrl) {
    if (kIsWeb) return 0;
    try {
      final uri = Uri.parse(resolvedUrl);
      if (uri.scheme != 'file') return 0;
      final file = File(uri.toFilePath());
      if (!file.existsSync()) return 0;
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  /// 播放。
  /// Start playback.
  Future<void> play() => _nativeController.play();

  /// 暂停。
  /// Pause playback.
  Future<void> pause() => _nativeController.pause();

  /// 切换播放/暂停。
  /// Toggle play/pause.
  Future<void> playOrPause() async {
    if (isPlaying.value) {
      await _nativeController.pause();
    } else {
      await _nativeController.play();
    }
  }

  /// 跳转到指定位置。
  /// Seek to the specified position.
  Future<void> seek(Duration position) async {
    await _nativeController.seek(position.inMilliseconds);
    if (currentUrl.value != null && FlutterCacheVideoPlayer.instance.isInitialized) {
      final byteOffset = _estimateByteOffset(position);
      FlutterCacheVideoPlayer.instance.downloadManager.onSeek(byteOffset);
    }
  }

  /// 设置音量（0.0 ~ 1.0）。
  /// Sets the volume (0.0 – 1.0).
  Future<void> setVolume(double value) async {
    await _nativeController.setVolume(value);
    volume.value = value.clamp(0.0, 1.0);
  }

  /// 设置播放速度。
  /// Sets the playback speed.
  Future<void> setSpeed(double value) async {
    await _nativeController.setSpeed(value);
    speed.value = value;
  }

  /// 停止播放并保存当前位置。
  /// Stops playback and saves the current position.
  Future<void> stop() async {
    await _saveCurrentPosition();
    await _nativeController.pause();
    playState.value = PlayState.stopped;
  }

  /// 对当前画面截图，返回一个 PNG 文件（[XFile]）。
  ///
  /// * [savePath] 可选，指定输出文件路径；不传则写入应用临时目录。Web 上忽略此参数。
  /// * 未加载媒体时抛出 [StateError]。
  ///
  /// Take a snapshot of the currently rendered frame and return it as a PNG
  /// [XFile]. On native platforms [XFile.path] is an absolute file path; on
  /// web it is a `blob:` URL. Throws [StateError] if no media is loaded.
  Future<XFile> takeSnapshot({String? savePath}) async {
    if (currentUrl.value == null) {
      throw StateError('No media is currently loaded.');
    }
    return _nativeController.takeSnapshot(savePath: savePath);
  }

  Future<void> _saveCurrentPosition() async {
    if (currentUrl.value == null) return;
    if (position.value.inMilliseconds <= 0) return;
    if (!FlutterCacheVideoPlayer.instance.isInitialized) return;

    final urlHash = UrlHasher.hash(currentUrl.value!);
    await FlutterCacheVideoPlayer.instance.historyRepo.savePosition(
      urlHash,
      position.value.inMilliseconds,
      duration.value.inMilliseconds,
    );
  }

  /// 释放资源，取消监听并关闭播放器。
  /// Disposes resources, cancels subscriptions, and releases the player.
  Future<void> dispose() async {
    await _saveCurrentPosition();
    await _cancelCacheSubscriptions();
    for (final disposer in _disposers) {
      disposer();
    }
    _disposers.clear();
    await _nativeController.dispose();
  }

  Future<void> _cancelCacheSubscriptions() async {
    await _bitmapSubscription?.cancel();
    _bitmapSubscription = null;
    await _mediaIndexSubscription?.cancel();
    _mediaIndexSubscription = null;
    _currentTotalChunks = 0;
  }

  /// 订阅当前媒体的缓存进度，实时更新 [cachedProgress] 等 signals。
  /// Subscribes to the download bitmap for [url] and drives cache signals.
  Future<void> _subscribeCacheProgress(String url) async {
    await _cancelCacheSubscriptions();
    final urlHash = UrlHasher.hash(url);
    final repo = FlutterCacheVideoPlayer.instance.cacheRepo;

    try {
      final existing = await repo.findByHash(urlHash);
      if (existing != null) {
        _currentTotalChunks = existing.totalChunks;
        isFullyCached.value = existing.isCompleted;
        final bitmap = await repo.getBitmap(urlHash);
        if (bitmap != null) {
          _applyBitmap(bitmap);
        }
      }
    } catch (_) {}

    _mediaIndexSubscription = repo.watchMediaIndex(urlHash).listen((rows) {
      if (rows.isEmpty) return;
      final index = rows.first;
      final total = (index['total_chunks'] as int?) ?? 0;
      final completed = (index['is_completed'] as int?) == 1;
      if (total > 0) _currentTotalChunks = total;
      isFullyCached.value = completed;
    }, onError: (_) {});

    _bitmapSubscription = repo.watchBitmap(urlHash).listen((rows) {
      if (rows.isEmpty) return;
      try {
        final bitmap = ChunkBitmap.fromMap(rows.first);
        _applyBitmap(bitmap);
      } catch (_) {}
    }, onError: (_) {});
  }

  void _applyBitmap(ChunkBitmap bitmap) {
    downloadedBytes.value = bitmap.downloadedBytes;
    if (_currentTotalChunks > 0) {
      cachedProgress.value = bitmap.getProgress(_currentTotalChunks).clamp(0.0, 1.0);
    }
  }

  /// 重置所有状态为初始值。
  /// Resets all state to initial values.
  void reset() {
    _hasPlayedSinceOpen = false;
    _hasReadySinceOpen = false;
    batch(() {
      playState.value = PlayState.idle;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      isBuffering.value = false;
      errorMessage.value = null;
      currentUrl.value = null;
      mimeType.value = null;
      cachedProgress.value = 0.0;
      downloadedBytes.value = 0;
      isFullyCached.value = false;
      videoSize.value = Size.zero;
    });
  }
}
