import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

/// 播放列表面板：列表 + 随机/循环控制。
class PlaylistSection extends StatefulWidget {
  final FlutterCacheVideoPlayer app;
  const PlaylistSection({super.key, required this.app});

  @override
  State<PlaylistSection> createState() => _PlaylistSectionState();
}

class _PlaylistSectionState extends State<PlaylistSection> with SignalsMixin {
  late final _shuffle = createSignal(false);
  late final _repeat = createSignal(false);

  FlutterCacheVideoPlaylistController get _mgr => widget.app.playlistController;

  @override
  void initState() {
    super.initState();
    _shuffle.value = _mgr.shuffle;
    _repeat.value = _mgr.repeat;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _mgr.items;
    final activeIdx = _mgr.currentIndex.watch(context);
    final shuffleOn = _shuffle.watch(context);
    final repeatOn = _repeat.watch(context);

    if (items.isEmpty) {
      return const Center(child: Text('播放列表为空'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text('播放列表', style: theme.textTheme.titleMedium),
              const Spacer(),
              Text('${items.length} 项', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final active = index == activeIdx;
              return ListTile(
                leading: active
                    ? Icon(Icons.play_arrow, color: theme.colorScheme.primary)
                    : Text('${index + 1}', style: theme.textTheme.bodyMedium),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: active
                      ? TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)
                      : null,
                ),
                onTap: () => _mgr.playIndex(index),
                selected: active,
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle, color: shuffleOn ? theme.colorScheme.primary : null),
                onPressed: () {
                  _mgr.toggleShuffle();
                  _shuffle.value = _mgr.shuffle;
                },
              ),
              IconButton(
                icon: Icon(Icons.repeat, color: repeatOn ? theme.colorScheme.primary : null),
                onPressed: () {
                  _mgr.toggleRepeat();
                  _repeat.value = _mgr.repeat;
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
