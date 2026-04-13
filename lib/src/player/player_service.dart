import 'dart:async';
import '../core/constants.dart';
import '../core/logger.dart';
import '../data/repositories/cache_repository.dart';
import '../data/repositories/history_repository.dart';
import '../download/download_manager.dart';
import '../proxy/mime_detector.dart';
import '../utils/url_hasher.dart';
import 'native_player_controller.dart';
import 'player_state.dart';
import 'platform_player_factory.dart';

/// 播放服务，封装 NativePlayerController 并管理生命周期、事件监听和历史持久化。
/// Player service wrapping NativePlayerController with lifecycle management, event listeners, and history persistence.
class PlayerService {
  final CacheConfig config;
  final PlatformPlayerFactory playerFactory;
  final CacheRepository cacheRepo;
  final HistoryRepository historyRepo;
  final DownloadManager downloadManager;
  final PlayerState state = PlayerState();

  late final NativePlayerController _controller;
  final List<StreamSubscription> _subscriptions = [];

  /// 防止旧媒体的残留事件干扰新媒体的状态。open() 时重置为 false，
  /// 收到新媒体的 playing(true) 后置为 true。
  /// Guards against stale native events from the previous media session.
  /// Reset to false on open(), set to true when playing(true) is received.
  bool _hasPlayedSinceOpen = false;

  PlayerService({
    required this.config,
    required this.playerFactory,
    required this.cacheRepo,
    required this.historyRepo,
    required this.downloadManager,
  }) {
    _controller = NativePlayerController();
  }

  /// 原生播放器控制器。
  /// The native player controller.
  NativePlayerController get controller => _controller;

  /// 原生纹理 ID，用于 Texture widget。
  /// Native texture ID for the Texture widget.
  int? get textureId => _controller.textureId;

  /// 初始化原生播放器（创建纹理并设置事件监听）。
  /// Initializes the native player (creates texture and sets up event listeners).
  Future<void> init() async {
    await _controller.create();
    _setupListeners();
  }

  void _setupListeners() {
    _subscriptions.add(
      _controller.playingStream.listen((playing) {
        if (playing) {
          _hasPlayedSinceOpen = true;
        } else if (!_hasPlayedSinceOpen) {
          // 忽略旧媒体残留的 paused 事件。
          // Ignore stale paused event from a previous media session.
          Logger.warning('Ignoring stale paused event before first playing(true)');
          return;
        }
        state.setPlayState(playing ? PlayState.playing : PlayState.paused);
      }),
    );

    _subscriptions.add(
      _controller.positionStream.listen((position) {
        state.setPosition(position);
        // 注意：不在此处调用 downloadManager.onSeek()，仅在用户主动 seek 时调用。
        // 每 200ms 的位置更新若触发 onSeek 会持续取消下载工作线程，导致分片永远无法完成。
        // Note: do NOT call downloadManager.onSeek() here. Only call it on
        // explicit user seeks. Position updates fire every ~200ms and onSeek()
        // cancels all active workers, preventing chunks from ever completing.
      }),
    );

    _subscriptions.add(
      _controller.durationStream.listen((duration) {
        state.setDuration(duration);
      }),
    );

    _subscriptions.add(
      _controller.bufferingStream.listen((buffering) {
        state.setBuffering(buffering);
      }),
    );

    _subscriptions.add(
      _controller.errorStream.listen((error) {
        Logger.error('Player error: $error');
        state.setError(error);
      }),
    );

    _subscriptions.add(
      _controller.completedStream.listen((_) {
        if (!_hasPlayedSinceOpen) {
          // 旧媒体的 completed 事件在新媒体 open() 后到达——忽略。
          // Stale completed event from the previous media arrived after open() — ignore.
          Logger.warning('Ignoring stale completed event before first playing(true)');
          return;
        }
        Logger.info('Playback completed');
        state.setPlayState(PlayState.stopped);
      }),
    );
  }

  int _estimateByteOffset(Duration position) {
    if (state.duration.inMilliseconds == 0) return 0;
    return 0;
  }

  /// 打开指定 URL 的媒体。[resumeHistory] 为 true 时恢复上次播放位置，默认从头播放。
  /// Opens the media at the given URL. When [resumeHistory] is true, resumes the last position; otherwise starts from the beginning.
  Future<void> open(String url, {bool resumeHistory = false}) async {
    try {
      await _saveCurrentPosition();

      _hasPlayedSinceOpen = false;
      state.reset();
      state.setCurrentUrl(url);

      final mimeType = MimeDetector.detect(url);
      state.setMimeType(mimeType);

      state.setPlayState(PlayState.loading);

      final mediaUrl = playerFactory.createMediaUrl(url);
      Logger.info('Opening media: $url → $mediaUrl');

      await _controller.open(mediaUrl);

      if (resumeHistory) {
        final urlHash = UrlHasher.hash(url);
        try {
          final history = await historyRepo.getLastPosition(urlHash);
          if (history != null && history.positionMs > 0) {
            Future.delayed(const Duration(milliseconds: 500), () {
              _controller.seek(history.positionMs);
            });
          }
        } catch (e) {
          Logger.error('Failed to get history for $urlHash', e);
        }
      }
    } catch (e, st) {
      Logger.error('Failed to open media: $url', e, st);
      state.setError(e.toString());
    }
  }

  /// 播放。
  /// Start playback.
  Future<void> play() => _controller.play();

  /// 暂停。
  /// Pause playback.
  Future<void> pause() => _controller.pause();

  /// 切换播放/暂停。
  /// Toggle play/pause.
  Future<void> playOrPause() async {
    if (state.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }
  }

  /// 跳转到指定位置。
  /// Seek to the specified position.
  Future<void> seek(Duration position) async {
    await _controller.seek(position.inMilliseconds);
    if (state.currentUrl != null) {
      final byteOffset = _estimateByteOffset(position);
      downloadManager.onSeek(byteOffset);
    }
  }

  /// 设置音量（0.0 ~ 1.0）。
  /// Sets the volume (0.0 – 1.0).
  Future<void> setVolume(double volume) async {
    await _controller.setVolume(volume);
    state.setVolume(volume);
  }

  /// 设置播放速度。
  /// Sets the playback speed.
  Future<void> setSpeed(double speed) async {
    await _controller.setSpeed(speed);
    state.setSpeed(speed);
  }

  /// 停止播放并保存当前位置。
  /// Stops playback and saves the current position.
  Future<void> stop() async {
    await _saveCurrentPosition();
    await _controller.pause();
    state.setPlayState(PlayState.stopped);
  }

  Future<void> _saveCurrentPosition() async {
    if (state.currentUrl == null) return;
    if (state.position.inMilliseconds <= 0) return;

    final urlHash = UrlHasher.hash(state.currentUrl!);
    await historyRepo.savePosition(
      urlHash,
      state.position.inMilliseconds,
      state.duration.inMilliseconds,
    );
  }

  /// 释放资源，取消监听并关闭播放器。
  /// Disposes resources, cancels subscriptions, and releases the player.
  Future<void> dispose() async {
    await _saveCurrentPosition();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _controller.dispose();
    state.dispose();
  }
}
