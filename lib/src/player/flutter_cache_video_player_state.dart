import 'package:signals/signals.dart';

/// 播放状态枚举。
/// Playback state enumeration.
enum PlayState { idle, loading, playing, paused, stopped, error }

/// 响应式播放器状态，基于 Signals 驱动 UI 更新。
/// Reactive player state based on Signals for driving UI updates.
class FlutterCacheVideoPlayerState {
  final playState = signal(PlayState.idle);
  final position = signal(Duration.zero);
  final duration = signal(Duration.zero);
  final volume = signal(1.0);
  final speed = signal(1.0);
  final isBuffering = signal(false);
  final errorMessage = signal<String?>(null);
  final currentUrl = signal<String?>(null);
  final mimeType = signal<String?>(null);

  late final isVideo = computed(() => mimeType.value?.startsWith('video/') ?? false);
  late final isAudio = computed(() => mimeType.value?.startsWith('audio/') ?? false);
  late final isPlaying = computed(() => playState.value == PlayState.playing);
  late final progressPercent = computed(() {
    if (duration.value.inMilliseconds == 0) return 0.0;
    return position.value.inMilliseconds / duration.value.inMilliseconds;
  });

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
    });
  }
}
