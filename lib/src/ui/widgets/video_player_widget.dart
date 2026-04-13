import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../data/models/chunk_bitmap.dart';
import '../../player/player_service.dart';
import '../../player/player_state.dart';
import 'progress_bar.dart';

/// 视频播放器组件，使用原生 Texture 渲染视频画面并提供自定义控制栏。
/// Video player widget using native Texture rendering with custom controls.
class VideoPlayerWidget extends StatefulWidget {
  final PlayerService playerService;
  final ChunkBitmap? bitmap;
  final int totalChunks;

  const VideoPlayerWidget({
    super.key,
    required this.playerService,
    this.bitmap,
    this.totalChunks = 0,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> with SignalsMixin {
  late final _playState = createSignal(PlayState.idle);
  late final _position = createSignal(Duration.zero);
  late final _duration = createSignal(Duration.zero);
  late final _isBuffering = createSignal(false);
  late final _errorMsg = createSignal<String?>(null);

  PlayerService get _svc => widget.playerService;

  @override
  void initState() {
    super.initState();
    _svc.state.addListener(_sync);
    _sync();
  }

  void _sync() {
    final s = _svc.state;
    _playState.value = s.playState;
    _position.value = s.position;
    _duration.value = s.duration;
    _isBuffering.value = s.isBuffering;
    _errorMsg.value = s.errorMessage;
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerService != widget.playerService) {
      oldWidget.playerService.state.removeListener(_sync);
      _svc.state.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    _svc.state.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ps = _playState.watch(context);
    final err = _errorMsg.watch(context);
    final buffering = _isBuffering.watch(context);

    return Column(
      children: [
        Expanded(child: _buildVideoSurface(ps, err, buffering)),
        _VideoControls(
          playerService: _svc,
          playState: _playState,
          position: _position,
          duration: _duration,
          bitmap: widget.bitmap,
          totalChunks: widget.totalChunks,
        ),
      ],
    );
  }

  Widget _buildVideoSurface(PlayState ps, String? err, bool buffering) {
    // Error
    if (ps == PlayState.error) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  err ?? '播放失败',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  if (_svc.state.currentUrl != null) {
                    _svc.open(_svc.state.currentUrl!);
                  }
                },
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('重试', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    // Loading / buffering
    if (ps == PlayState.loading || buffering) {
      if (kIsWeb) {
        return Container(
          color: Colors.black,
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      final textureId = _svc.textureId;
      return Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (textureId != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Texture(textureId: textureId),
              ),
            const CircularProgressIndicator(),
          ],
        ),
      );
    }

    if (kIsWeb) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: HtmlElementView(viewType: 'flutter-cache-video-player-web'),
          ),
        ),
      );
    }
    final textureId = _svc.textureId;
    if (textureId == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Texture(textureId: textureId),
        ),
      ),
    );
  }
}

/// 视频控制栏，独立 Widget 以实现细粒度 Signal 重建。
/// Video controls bar as a separate Widget for fine-grained Signal rebuilds.
class _VideoControls extends StatelessWidget {
  final PlayerService playerService;
  final ReadonlySignal<PlayState> playState;
  final ReadonlySignal<Duration> position;
  final ReadonlySignal<Duration> duration;
  final ChunkBitmap? bitmap;
  final int totalChunks;

  const _VideoControls({
    required this.playerService,
    required this.playState,
    required this.position,
    required this.duration,
    this.bitmap,
    this.totalChunks = 0,
  });

  @override
  Widget build(BuildContext context) {
    final ps = playState.watch(context);
    final pos = position.watch(context);
    final dur = duration.watch(context);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressBar(
              position: position,
              duration: duration,
              bitmap: bitmap,
              totalChunks: totalChunks,
              onSeek: (p) => playerService.seek(p),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  onPressed: () {
                    final newPos = pos - const Duration(seconds: 10);
                    playerService.seek(newPos < Duration.zero ? Duration.zero : newPos);
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 40,
                  icon: Icon(ps == PlayState.playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () => playerService.playOrPause(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  onPressed: () {
                    final newPos = pos + const Duration(seconds: 10);
                    playerService.seek(newPos > dur ? dur : newPos);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
