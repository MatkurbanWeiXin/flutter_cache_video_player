import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

/// 播放控制栏：进度条 + 播放/暂停/跳转按钮。
class ControlsBar extends StatelessWidget {
  final FlutterCacheVideoPlayer app;
  final ReadonlySignal<PlayState> playState;
  final ReadonlySignal<Duration> position;
  final ReadonlySignal<Duration> duration;

  const ControlsBar({
    super.key,
    required this.app,
    required this.playState,
    required this.position,
    required this.duration,
  });

  PlayerService get _svc => app.playerService;

  @override
  Widget build(BuildContext context) {
    final ps = playState.watch(context);
    final pos = position.watch(context);
    final dur = duration.watch(context);
    final isPlaying = ps == PlayState.playing;
    final textStyle = Theme.of(context).textTheme.bodySmall!;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_fmt(pos), style: textStyle),
                  Expanded(
                    child: Slider(
                      value: dur.inMilliseconds > 0
                          ? pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble()
                          : 0,
                      max: dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1,
                      onChanged: (v) => _svc.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Text(_fmt(dur), style: textStyle),
                ],
              ),
            ),
            // 按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () => app.playlistManager.previous(),
                ),
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  onPressed: () {
                    final n = pos - const Duration(seconds: 10);
                    _svc.seek(n < Duration.zero ? Duration.zero : n);
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 40,
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () => _svc.playOrPause(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  onPressed: () {
                    final n = pos + const Duration(seconds: 10);
                    _svc.seek(n > dur ? dur : n);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => app.playlistManager.next(),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
