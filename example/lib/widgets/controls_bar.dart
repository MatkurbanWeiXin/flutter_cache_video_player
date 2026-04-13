import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

/// 播放控制栏：进度条 + 播放/暂停/跳转按钮。
class ControlsBar extends StatelessWidget {
  final FlutterCacheVideoPlayer app;

  const ControlsBar({super.key, required this.app});

  FlutterCacheVideoPlayerController get _ctrl => app.controller;

  @override
  Widget build(BuildContext context) {
    final ps = _ctrl.state.playState.watch(context);
    final pos = _ctrl.state.position.watch(context);
    final dur = _ctrl.state.duration.watch(context);
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
                          ? pos.inMilliseconds
                                .clamp(0, dur.inMilliseconds)
                                .toDouble()
                          : 0,
                      max: dur.inMilliseconds > 0
                          ? dur.inMilliseconds.toDouble()
                          : 1,
                      onChanged: (v) =>
                          _ctrl.seek(Duration(milliseconds: v.toInt())),
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
                  onPressed: () => app.playlistController.previous(),
                ),
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  onPressed: () {
                    final n = pos - const Duration(seconds: 10);
                    _ctrl.seek(n < Duration.zero ? Duration.zero : n);
                  },
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 40,
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                  onPressed: () => _ctrl.playOrPause(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.forward_10),
                  onPressed: () {
                    final n = pos + const Duration(seconds: 10);
                    _ctrl.seek(n > dur ? dur : n);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: () => app.playlistController.next(),
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
