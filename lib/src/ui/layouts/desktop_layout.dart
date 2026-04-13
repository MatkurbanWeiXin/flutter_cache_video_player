import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../player/player_service.dart';
import '../../player/playlist_manager.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/playlist_panel.dart';

/// 桌面布局，可选侧边导航 + 播放器 + 播放列表。
/// Desktop layout with optional side navigation, player, and playlist.
class DesktopLayout extends StatefulWidget {
  final PlayerService? playerService;
  final PlaylistManager? playlistManager;
  final Widget? sideNavigation;

  const DesktopLayout({super.key, this.playerService, this.playlistManager, this.sideNavigation});

  @override
  State<DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<DesktopLayout> with SignalsMixin {
  late final _isVideo = createSignal(false);

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
  void didUpdateWidget(DesktopLayout oldWidget) {
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
          // Side navigation
          if (widget.sideNavigation != null) SizedBox(width: 72, child: widget.sideNavigation),
          // Player area
          Expanded(
            child: isVideo
                ? VideoPlayerWidget(playerService: widget.playerService!)
                : AudioPlayerWidget(playerService: widget.playerService!),
          ),
          // Playlist
          if (widget.playlistManager != null)
            SizedBox(width: 320, child: PlaylistPanel(playlistManager: widget.playlistManager!)),
        ],
      ),
    );
  }
}
