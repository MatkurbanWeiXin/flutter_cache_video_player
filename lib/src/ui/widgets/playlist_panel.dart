import 'dart:async';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../player/playlist_manager.dart';

/// 播放列表面板组件，展示播放列表并提供随机/循环/上一曲/下一曲控制。
/// Playlist panel widget displaying the playlist with shuffle/repeat/prev/next controls.
class PlaylistPanel extends StatefulWidget {
  final PlaylistManager playlistManager;

  const PlaylistPanel({super.key, required this.playlistManager});

  @override
  State<PlaylistPanel> createState() => _PlaylistPanelState();
}

class _PlaylistPanelState extends State<PlaylistPanel> with SignalsMixin {
  late final _currentIndex = createSignal(-1);
  late final _shuffle = createSignal(false);
  late final _repeat = createSignal(false);
  StreamSubscription<int>? _indexSub;

  PlaylistManager get _mgr => widget.playlistManager;

  @override
  void initState() {
    super.initState();
    _currentIndex.value = _mgr.currentIndex;
    _shuffle.value = _mgr.shuffle;
    _repeat.value = _mgr.repeat;
    _indexSub = _mgr.indexStream.listen((i) => _currentIndex.value = i);
  }

  @override
  void didUpdateWidget(PlaylistPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistManager != widget.playlistManager) {
      _indexSub?.cancel();
      _currentIndex.value = _mgr.currentIndex;
      _shuffle.value = _mgr.shuffle;
      _repeat.value = _mgr.repeat;
      _indexSub = _mgr.indexStream.listen((i) => _currentIndex.value = i);
    }
  }

  @override
  void dispose() {
    _indexSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _mgr.items;
    final activeIdx = _currentIndex.watch(context);
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
              final isActive = index == activeIdx;
              return ListTile(
                leading: isActive
                    ? Icon(Icons.play_arrow, color: theme.colorScheme.primary)
                    : Text('${index + 1}', style: theme.textTheme.bodyMedium),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isActive
                      ? TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)
                      : null,
                ),
                onTap: () => _mgr.playIndex(index),
                selected: isActive,
              );
            },
          ),
        ),
        // Controls
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.shuffle, color: shuffleOn ? theme.colorScheme.primary : null),
                onPressed: () {
                  _mgr.toggleShuffle();
                  _shuffle.value = _mgr.shuffle;
                },
                tooltip: '随机播放',
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous),
                onPressed: () => _mgr.previous(),
                tooltip: '上一首',
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: () => _mgr.next(),
                tooltip: '下一首',
              ),
              IconButton(
                icon: Icon(Icons.repeat, color: repeatOn ? theme.colorScheme.primary : null),
                onPressed: () {
                  _mgr.toggleRepeat();
                  _repeat.value = _mgr.repeat;
                },
                tooltip: '循环播放',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
