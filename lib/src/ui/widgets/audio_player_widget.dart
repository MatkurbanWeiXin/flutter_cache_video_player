import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../data/models/chunk_bitmap.dart';
import '../../player/player_service.dart';
import '../../player/player_state.dart';
import 'progress_bar.dart';

/// 音频播放器组件，包含封面图、标题和控制栏。
/// Audio player widget containing cover art, title, and controls.
class AudioPlayerWidget extends StatefulWidget {
  final PlayerService playerService;
  final ChunkBitmap? bitmap;
  final int totalChunks;
  final String? title;
  final String? coverUrl;

  const AudioPlayerWidget({
    super.key,
    required this.playerService,
    this.bitmap,
    this.totalChunks = 0,
    this.title,
    this.coverUrl,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> with SignalsMixin {
  late final _playState = createSignal(PlayState.idle);
  late final _position = createSignal(Duration.zero);
  late final _duration = createSignal(Duration.zero);

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
  }

  @override
  void didUpdateWidget(AudioPlayerWidget oldWidget) {
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
    final theme = Theme.of(context);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Cover art
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.music_note, size: 80),
        ),
        const SizedBox(height: 24),
        // Title
        if (widget.title != null)
          Text(widget.title!, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        // Controls
        _AudioControls(
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
}

/// 音频控制栏，独立 Widget 以实现细粒度 Signal 重建。
/// Audio controls bar as a separate Widget for fine-grained Signal rebuilds.
class _AudioControls extends StatelessWidget {
  final PlayerService playerService;
  final ReadonlySignal<PlayState> playState;
  final ReadonlySignal<Duration> position;
  final ReadonlySignal<Duration> duration;
  final ChunkBitmap? bitmap;
  final int totalChunks;

  const _AudioControls({
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress
        ProgressBar(
          position: position,
          duration: duration,
          bitmap: bitmap,
          totalChunks: totalChunks,
          onSeek: (p) => playerService.seek(p),
        ),
        // Controls
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
            const SizedBox(width: 16),
            IconButton.filled(
              iconSize: 48,
              icon: Icon(ps == PlayState.playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => playerService.playOrPause(),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.forward_10),
              onPressed: () {
                final newPos = pos + const Duration(seconds: 10);
                playerService.seek(newPos > dur ? dur : newPos);
              },
            ),
          ],
        ),
      ],
    );
  }
}
