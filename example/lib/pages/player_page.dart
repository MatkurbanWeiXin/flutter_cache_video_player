import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

import '../widgets/controls_bar.dart';
import '../widgets/playlist_section.dart';
import '../widgets/video_surface.dart';

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
          appBar: AppBar(
            title: const Text('Cache Video Player'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SettingsSheet(themeController: app.themeController),
                ),
              ),
            ],
          ),
          body: body,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Player area – bridges PlayerState (ChangeNotifier) → Signals
// Only used inside PlayerPage, not reusable elsewhere.
// ---------------------------------------------------------------------------
class _PlayerArea extends StatefulWidget {
  final FlutterCacheVideoPlayer app;
  const _PlayerArea({required this.app});

  @override
  State<_PlayerArea> createState() => _PlayerAreaState();
}

class _PlayerAreaState extends State<_PlayerArea> with SignalsMixin {
  late final _playState = createSignal(PlayState.idle);
  late final _position = createSignal(Duration.zero);
  late final _duration = createSignal(Duration.zero);
  late final _isBuffering = createSignal(false);
  late final _errorMsg = createSignal<String?>(null);

  PlayerService get _svc => widget.app.playerService;

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
    _isBuffering.value = s.isBuffering;
    _errorMsg.value = s.errorMessage;
  }

  @override
  void dispose() {
    _svc.state.removeListener(_sync);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: VideoSurface(
            playerService: _svc,
            playState: _playState,
            isBuffering: _isBuffering,
            errorMessage: _errorMsg,
          ),
        ),
        ControlsBar(
          app: widget.app,
          playState: _playState,
          position: _position,
          duration: _duration,
        ),
      ],
    );
  }
}
