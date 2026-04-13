import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../player/player_service.dart';
import '../../player/playlist_manager.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/playlist_panel.dart';

/// 平板布局，播放器 + 可折叠播放列表面板。
/// Tablet layout with the player and a collapsible playlist panel.
class TabletLayout extends StatefulWidget {
  final PlayerService? playerService;
  final PlaylistManager? playlistManager;

  const TabletLayout({super.key, this.playerService, this.playlistManager});

  @override
  State<TabletLayout> createState() => _TabletLayoutState();
}

class _TabletLayoutState extends State<TabletLayout> with SignalsMixin {
  late final _isVideo = createSignal(false);
  bool _showPlaylist = true;

  @override
  void initState() {
    super.initState();
    widget.playerService?.state.addListener(_sync);
    _sync();
  }

  void _sync() {
    _isVideo.value = widget.playerService?.state.isVideo ?? false;
  }

  @override
  void didUpdateWidget(TabletLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerService != widget.playerService) {
      oldWidget.playerService?.state.removeListener(_sync);
      widget.playerService?.state.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.playerService?.state.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playerService == null) {
      return const Scaffold(body: Center(child: Text('请选择一个媒体文件')));
    }

    final isVideo = _isVideo.watch(context);
    return Scaffold(
      body: Row(
        children: [
          // Player area
          Expanded(
            flex: 3,
            child: isVideo
                ? VideoPlayerWidget(playerService: widget.playerService!)
                : AudioPlayerWidget(playerService: widget.playerService!),
          ),
          // Playlist panel (collapsible)
          if (_showPlaylist && widget.playlistManager != null)
            SizedBox(width: 300, child: PlaylistPanel(playlistManager: widget.playlistManager!)),
        ],
      ),
      floatingActionButton: widget.playlistManager != null
          ? FloatingActionButton.small(
              onPressed: () => setState(() => _showPlaylist = !_showPlaylist),
              child: Icon(_showPlaylist ? Icons.playlist_remove : Icons.playlist_play),
            )
          : null,
    );
  }
}
