import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../data/models/chunk_bitmap.dart';
import 'cache_indicator.dart';

/// 进度条组件，包含 Seek 滑块、缓存指示器和时间标签。
/// Progress bar containing a seek slider, cache indicator, and time labels.
class ProgressBar extends StatefulWidget {
  final ReadonlySignal<Duration> position;
  final ReadonlySignal<Duration> duration;
  final ChunkBitmap? bitmap;
  final int totalChunks;
  final ValueChanged<Duration>? onSeek;

  const ProgressBar({
    super.key,
    required this.position,
    required this.duration,
    this.bitmap,
    this.totalChunks = 0,
    this.onSeek,
  });

  @override
  State<ProgressBar> createState() => _ProgressBarState();
}

class _ProgressBarState extends State<ProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = widget.position.watch(context);
    final duration = widget.duration.watch(context);
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Cache indicator
        CacheIndicator(
          bitmap: widget.bitmap,
          totalChunks: widget.totalChunks,
          height: 3,
          cachedColor: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
        // Seek slider
        SliderTheme(
          data: theme.sliderTheme,
          child: Slider(
            value: _isDragging ? _dragValue : progress.clamp(0.0, 1.0),
            onChangeStart: (value) {
              setState(() {
                _isDragging = true;
                _dragValue = value;
              });
            },
            onChanged: (value) {
              setState(() => _dragValue = value);
            },
            onChangeEnd: (value) {
              setState(() => _isDragging = false);
              final seekPosition = Duration(
                milliseconds: (value * duration.inMilliseconds).round(),
              );
              widget.onSeek?.call(seekPosition);
            },
          ),
        ),
        // Time labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position), style: theme.textTheme.bodySmall),
              Text(_formatDuration(duration), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
