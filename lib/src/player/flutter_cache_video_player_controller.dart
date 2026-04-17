import 'dart:async';
import 'dart:ui';

import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'native_player_controller.dart';

/// 播放控制器，封装 NativePlayerController 并管理生命周期、事件监听和历史持久化。
/// Player controller wrapping NativePlayerController with lifecycle management, event listeners, and history persistence.
class FlutterCacheVideoPlayerController {
  late final NativePlayerController _nativeController;

  final List<VoidCallback> _disposers = <VoidCallback>[];

  /// 防止旧媒体的残留事件干扰新媒体的状态。open() 时重置为 false，
  /// 收到新媒体的 playing(true) 后置为 true。
  /// Guards against stale native events from the previous media session.
  /// Reset to false on open(), set to true when playing(true) is received.
  bool _hasPlayedSinceOpen = false;

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
  final FlutterSignal<double> bufferedProgress = signal<double>(0.0);

  /// 当前媒体已缓存字节数。
  /// Bytes downloaded for the current media.
  final FlutterSignal<int> downloadedBytes = signal<int>(0);

  /// 当前媒体是否已完整缓存。
  /// Whether the current media is fully cached.
  final FlutterSignal<bool> isFullyCached = signal<bool>(false);

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

  FlutterCacheVideoPlayerController() {
    _nativeController = NativePlayerController();
  }

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
        if (wasFirstPlay) {
          final dur = _nativeController.durationSignal.value;
          if (dur > Duration.zero) {
            duration.value = dur;
          }
        }
      } else if (!_hasPlayedSinceOpen) {
        return;
      }
      playState.value = playing ? PlayState.playing : PlayState.paused;
    });
    VoidCallback positionEffect = effect(() {
      final value = _nativeController.positionSignal.value;
      if (!_hasPlayedSinceOpen) return;
      position.value = value;
    });
    VoidCallback durationEffect = effect(() {
      final value = _nativeController.durationSignal.value;
      if (!_hasPlayedSinceOpen) return;
      duration.value = value;
    });
    VoidCallback bufferingEffect = effect(() {
      final buffering = _nativeController.bufferingSignal.value;
      if (!_hasPlayedSinceOpen) return;
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
    _disposers.addAll([
      playingEffect,
      positionEffect,
      durationEffect,
      bufferingEffect,
      errorEffect,
      completedEffect,
    ]);
  }

  int _estimateByteOffset(Duration position) {
    if (duration.value.inMilliseconds == 0) return 0;
    return 0;
  }

  /// 打开指定 URL 的媒体。[resumeHistory] 为 true 时恢复上次播放位置，默认从头播放。
  /// Opens the media at the given URL. When [resumeHistory] is true, resumes the last position; otherwise starts from the beginning.
  Future<void> open(String url, {bool resumeHistory = false}) async {
    try {
      await _saveCurrentPosition();

      _hasPlayedSinceOpen = false;
      reset();
      currentUrl.value = url;

      final type = MimeDetector.detect(url);
      mimeType.value = type;

      playState.value = PlayState.loading;

      final mediaUrl = await FlutterCacheVideoPlayer.instance.playerFactory.createMediaUrl(url);

      await _nativeController.open(mediaUrl);

      // Start watching cache progress from the plugin's cache repository.
      _subscribeCacheProgress(url);

      if (resumeHistory) {
        final urlHash = UrlHasher.hash(url);
        try {
          final history = await FlutterCacheVideoPlayer.instance.historyRepo.getLastPosition(
            urlHash,
          );
          if (history != null && history.positionMs > 0) {
            _nativeController.seek(history.positionMs);
          }
        } catch (_) {}
      }
    } catch (e) {
      errorMessage.value = e.toString();
      playState.value = PlayState.error;
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
    if (currentUrl.value != null) {
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

  Future<void> _saveCurrentPosition() async {
    if (currentUrl.value == null) return;
    if (position.value.inMilliseconds <= 0) return;

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

  /// 订阅当前媒体的缓存进度，实时更新 [bufferedProgress] 等 signals。
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
      bufferedProgress.value = bitmap.getProgress(_currentTotalChunks).clamp(0.0, 1.0);
    }
  }

  /// 重置所有状态为初始值。
  /// Resets all state to initial values.
  void reset() {
    batch(() {
      playState.value = PlayState.idle;
      position.value = Duration.zero;
      duration.value = Duration.zero;
      isBuffering.value = false;
      errorMessage.value = null;
      currentUrl.value = null;
      mimeType.value = null;
      bufferedProgress.value = 0.0;
      downloadedBytes.value = 0;
      isFullyCached.value = false;
    });
  }
}
