import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../../player/player_service.dart';
import '../../player/playlist_manager.dart';
import '../widgets/video_player_widget.dart';
import '../widgets/audio_player_widget.dart';

/// 移动端布局，单列显示视频或音频播放器。
/// Mobile layout rendering the video or audio player in a single column.
class MobileLayout extends StatefulWidget {
  final PlayerService? playerService;
  final PlaylistManager? playlistManager;

  const MobileLayout({super.key, this.playerService, this.playlistManager});

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout> with SignalsMixin {
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
  void didUpdateWidget(MobileLayout oldWidget) {
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
      body: isVideo
          ? VideoPlayerWidget(playerService: widget.playerService!)
          : AudioPlayerWidget(playerService: widget.playerService!),
    );
  }
}
