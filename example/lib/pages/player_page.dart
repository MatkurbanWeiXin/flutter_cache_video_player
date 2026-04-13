import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';

import '../widgets/controls_bar.dart';
import '../widgets/playlist_section.dart';

class PlayerPage extends StatelessWidget {
  final FlutterCacheVideoPlayer app;
  const PlayerPage({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final playerArea = _PlayerArea(app: app);
        final playlist = PlaylistSection(app: app);

        Widget body;
        if (constraints.maxWidth >= 900) {
          // Desktop
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: playerArea),
              SizedBox(width: 320, child: playlist),
            ],
          );
        } else if (constraints.maxWidth >= 600) {
          // Tablet
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: playerArea),
              SizedBox(width: 280, child: playlist),
            ],
          );
        } else {
          // Mobile
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: playerArea),
              SizedBox(height: 200, child: playlist),
            ],
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Cache Video Player')),
          body: body,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Player area — directly reads signals from the controller state.
// ---------------------------------------------------------------------------
class _PlayerArea extends StatelessWidget {
  final FlutterCacheVideoPlayer app;
  const _PlayerArea({required this.app});

  @override
  Widget build(BuildContext context) {
    final ctrl = app.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: FlutterCacheVideoPlayerView(controller: ctrl)),
        ControlsBar(app: app),
      ],
    );
  }
}
