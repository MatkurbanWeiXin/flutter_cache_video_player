import 'dart:async';
import 'package:signals/signals.dart';
import '../core/constants.dart';
import '../core/logger.dart';
import '../data/repositories/cache_repository.dart';
import '../data/repositories/history_repository.dart';
import '../download/download_manager.dart';
import '../proxy/mime_detector.dart';
import '../utils/url_hasher.dart';
import 'native_player_controller.dart';
import 'flutter_cache_video_player_state.dart';
import 'platform_player_factory.dart';

/// 播放控制器，封装 NativePlayerController 并管理生命周期、事件监听和历史持久化。
/// Player controller wrapping NativePlayerController with lifecycle management, event listeners, and history persistence.
class FlutterCacheVideoPlayerController {
  final CacheConfig config;
  final PlatformPlayerFactory playerFactory;
  final CacheRepository cacheRepo;
  final HistoryRepository historyRepo;
  final DownloadManager downloadManager;
  final FlutterCacheVideoPlayerState state = FlutterCacheVideoPlayerState();

  late final NativePlayerController _nativeController;
  final List<void Function()> _disposers = [];

  /// 防止旧媒体的残留事件干扰新媒体的状态。open() 时重置为 false，
  /// 收到新媒体的 playing(true) 后置为 true。
  /// Guards against stale native events from the previous media session.
  /// Reset to false on open(), set to true when playing(true) is received.
  bool _hasPlayedSinceOpen = false;

  FlutterCacheVideoPlayerController({
    required this.config,
    required this.playerFactory,
    required this.cacheRepo,
    required this.historyRepo,
    required this.downloadManager,
  }) {
    _nativeController = NativePlayerController();
  }

  /// 原生播放器控制器。
  /// The native player controller.
  NativePlayerController get nativeController => _nativeController;

  /// 原生纹理 ID，用于 Texture widget。
  /// Native texture ID for the Texture widget.
  int? get textureId => _nativeController.textureId;

  /// 初始化原生播放器（创建纹理并设置事件监听）。
  /// Initializes the native player (creates texture and sets up event listeners).
  Future<void> init() async {
    await _nativeController.create();
    _setupListeners();
  }

  void _setupListeners() {
    _disposers.add(
      effect(() {
        final playing = _nativeController.playingSignal.value;
        if (playing) {
          _hasPlayedSinceOpen = true;
        } else if (!_hasPlayedSinceOpen) {
          Logger.warning('Ignoring stale paused event before first playing(true)');
          return;
        }
        state.playState.value = playing ? PlayState.playing : PlayState.paused;
      }),
    );

    _disposers.add(
      effect(() {
        final position = _nativeController.positionSignal.value;
        if (!_hasPlayedSinceOpen) return;
        state.position.value = position;
      }),
    );

    _disposers.add(
      effect(() {
        final duration = _nativeController.durationSignal.value;
        if (!_hasPlayedSinceOpen) return;
        state.duration.value = duration;
      }),
    );

    _disposers.add(
      effect(() {
        final buffering = _nativeController.bufferingSignal.value;
        if (!_hasPlayedSinceOpen) return;
        state.isBuffering.value = buffering;
      }),
    );

    _disposers.add(
      effect(() {
        final error = _nativeController.errorSignal.value;
        if (error == null) return;
        Logger.error('Player error: $error');
        state.errorMessage.value = error;
        state.playState.value = PlayState.error;
      }),
    );

    _disposers.add(
      effect(() {
        _nativeController.completedSignal.value; // subscribe
        if (!_hasPlayedSinceOpen) {
          Logger.warning('Ignoring stale completed event before first playing(true)');
          return;
        }
        Logger.info('Playback completed');
        state.playState.value = PlayState.stopped;
      }),
    );
  }

  int _estimateByteOffset(Duration position) {
    if (state.duration.value.inMilliseconds == 0) return 0;
    return 0;
  }

  /// 打开指定 URL 的媒体。[resumeHistory] 为 true 时恢复上次播放位置，默认从头播放。
  /// Opens the media at the given URL. When [resumeHistory] is true, resumes the last position; otherwise starts from the beginning.
  Future<void> open(String url, {bool resumeHistory = false}) async {
    try {
      await _saveCurrentPosition();

      _hasPlayedSinceOpen = false;
      state.reset();
      state.currentUrl.value = url;

      final mimeType = MimeDetector.detect(url);
      state.mimeType.value = mimeType;

      state.playState.value = PlayState.loading;

      final mediaUrl = await playerFactory.createMediaUrl(url);
      Logger.info('Opening media: $url → $mediaUrl');

      await _nativeController.open(mediaUrl);

      if (resumeHistory) {
        final urlHash = UrlHasher.hash(url);
        try {
          final history = await historyRepo.getLastPosition(urlHash);
          if (history != null && history.positionMs > 0) {
            Future.delayed(const Duration(milliseconds: 500), () {
              _nativeController.seek(history.positionMs);
            });
          }
        } catch (e) {
          Logger.error('Failed to get history for $urlHash', e);
        }
      }
    } catch (e, st) {
      Logger.error('Failed to open media: $url', e, st);
      state.errorMessage.value = e.toString();
      state.playState.value = PlayState.error;
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
    if (state.isPlaying.value) {
      await _nativeController.pause();
    } else {
      await _nativeController.play();
    }
  }

  /// 跳转到指定位置。
  /// Seek to the specified position.
  Future<void> seek(Duration position) async {
    await _nativeController.seek(position.inMilliseconds);
    if (state.currentUrl.value != null) {
      final byteOffset = _estimateByteOffset(position);
      downloadManager.onSeek(byteOffset);
    }
  }

  /// 设置音量（0.0 ~ 1.0）。
  /// Sets the volume (0.0 – 1.0).
  Future<void> setVolume(double volume) async {
    await _nativeController.setVolume(volume);
    state.volume.value = volume.clamp(0.0, 1.0);
  }

  /// 设置播放速度。
  /// Sets the playback speed.
  Future<void> setSpeed(double speed) async {
    await _nativeController.setSpeed(speed);
    state.speed.value = speed;
  }

  /// 停止播放并保存当前位置。
  /// Stops playback and saves the current position.
  Future<void> stop() async {
    await _saveCurrentPosition();
    await _nativeController.pause();
    state.playState.value = PlayState.stopped;
  }

  Future<void> _saveCurrentPosition() async {
    if (state.currentUrl.value == null) return;
    if (state.position.value.inMilliseconds <= 0) return;

    final urlHash = UrlHasher.hash(state.currentUrl.value!);
    await historyRepo.savePosition(
      urlHash,
      state.position.value.inMilliseconds,
      state.duration.value.inMilliseconds,
    );
  }

  /// 释放资源，取消监听并关闭播放器。
  /// Disposes resources, cancels subscriptions, and releases the player.
  Future<void> dispose() async {
    await _saveCurrentPosition();
    for (final disposer in _disposers) {
      disposer();
    }
    _disposers.clear();
    await _nativeController.dispose();
  }
}
