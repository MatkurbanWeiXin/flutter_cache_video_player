import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> with SignalsMixin {
  late final _app = FlutterCacheVideoPlayer();
  late final _ready = createSignal(false);
  late final _error = createSignal<String?>(null);

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      await _app.init();
      _app.playlistManager.setPlaylist([
        const PlaylistItem(
          url:
              'https://videos.pexels.com/video-files/33538187/14261042_1080_1920_60fps.mp4',
          title: 'Test Video 1',
        ),
        const PlaylistItem(
          url:
              'https://videos.pexels.com/video-files/29603233/12740435_3840_2160_30fps.mp4',
          title: 'Test Video 2',
        ),
        const PlaylistItem(
          url:
              'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
          title: 'Butterfly',
        ),
      ]);
      _ready.value = true;
    } catch (e) {
      _error.value = e.toString();
    }
  }

  @override
  void dispose() {
    if (_ready.peek()) _app.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready.watch(context);
    final error = _error.watch(context);

    return MaterialApp(
      title: 'Cache Video Player',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      home: _buildHome(ready, error),
    );
  }

  Widget _buildHome(bool ready, String? error) {
    if (error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('初始化失败: $error'),
            ],
          ),
        ),
      );
    }
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _PlayerPage(app: _app);
  }
}

// ---------------------------------------------------------------------------
// Player page – adaptive layout (replaces breakpoint)
// ---------------------------------------------------------------------------
class _PlayerPage extends StatelessWidget {
  final FlutterCacheVideoPlayer app;
  const _PlayerPage({required this.app});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return _DesktopLayout(app: app);
        } else if (constraints.maxWidth >= 600) {
          return _TabletLayout(app: app);
        }
        return _MobileLayout(app: app);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile
// ---------------------------------------------------------------------------
class _MobileLayout extends StatelessWidget {
  final FlutterCacheVideoPlayer app;
  const _MobileLayout({required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context, app),
      body: Column(
        children: [
          Expanded(child: _PlayerArea(app: app)),
          SizedBox(height: 200, child: _PlaylistSection(app: app)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tablet
// ---------------------------------------------------------------------------
class _TabletLayout extends StatelessWidget {
  final FlutterCacheVideoPlayer app;
  const _TabletLayout({required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context, app),
      body: Row(
        children: [
          Expanded(flex: 2, child: _PlayerArea(app: app)),
          SizedBox(width: 280, child: _PlaylistSection(app: app)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop
// ---------------------------------------------------------------------------
class _DesktopLayout extends StatelessWidget {
  final FlutterCacheVideoPlayer app;
  const _DesktopLayout({required this.app});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context, app),
      body: Row(
        children: [
          Expanded(flex: 3, child: _PlayerArea(app: app)),
          SizedBox(width: 320, child: _PlaylistSection(app: app)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared AppBar
// ---------------------------------------------------------------------------
AppBar _buildAppBar(BuildContext context, FlutterCacheVideoPlayer app) {
  return AppBar(
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
  );
}

// ---------------------------------------------------------------------------
// Player area – bridges PlayerState (ChangeNotifier) → Signals
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
    final ps = _playState.watch(context);
    final err = _errorMsg.watch(context);
    final buffering = _isBuffering.watch(context);

    return Column(
      children: [
        Expanded(child: _buildSurface(context, ps, err, buffering)),
        _ControlsBar(
          app: widget.app,
          playState: _playState,
          position: _position,
          duration: _duration,
        ),
      ],
    );
  }

  Widget _buildSurface(
    BuildContext context,
    PlayState ps,
    String? err,
    bool buffering,
  ) {
    // Error
    if (ps == PlayState.error) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 48,
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  err ?? '播放失败',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  final url = _svc.state.currentUrl;
                  if (url != null) _svc.open(url);
                },
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('重试', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    // Loading / buffering
    if (ps == PlayState.loading || buffering) {
      return Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (!kIsWeb && _svc.textureId != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Texture(textureId: _svc.textureId!),
              ),
            const CircularProgressIndicator(),
          ],
        ),
      );
    }

    // Normal video
    if (kIsWeb) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: HtmlElementView(viewType: 'flutter-cache-video-player-web'),
          ),
        ),
      );
    }

    final textureId = _svc.textureId;
    if (textureId == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Texture(textureId: textureId),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls bar
// ---------------------------------------------------------------------------
class _ControlsBar extends StatelessWidget {
  final FlutterCacheVideoPlayer app;
  final ReadonlySignal<PlayState> playState;
  final ReadonlySignal<Duration> position;
  final ReadonlySignal<Duration> duration;

  const _ControlsBar({
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

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress slider
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(_fmt(pos), style: _ts(context)),
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
                          _svc.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Text(_fmt(dur), style: _ts(context)),
                ],
              ),
            ),
            // Buttons
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

  TextStyle _ts(BuildContext context) => Theme.of(context).textTheme.bodySmall!;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ---------------------------------------------------------------------------
// Playlist section
// ---------------------------------------------------------------------------
class _PlaylistSection extends StatefulWidget {
  final FlutterCacheVideoPlayer app;
  const _PlaylistSection({required this.app});

  @override
  State<_PlaylistSection> createState() => _PlaylistSectionState();
}

class _PlaylistSectionState extends State<_PlaylistSection> with SignalsMixin {
  late final _currentIndex = createSignal(-1);
  late final _shuffle = createSignal(false);
  late final _repeat = createSignal(false);
  StreamSubscription<int>? _sub;

  PlaylistManager get _mgr => widget.app.playlistManager;

  @override
  void initState() {
    super.initState();
    _currentIndex.value = _mgr.currentIndex;
    _shuffle.value = _mgr.shuffle;
    _repeat.value = _mgr.repeat;
    _sub = _mgr.indexStream.listen((i) => _currentIndex.value = i);
  }

  @override
  void dispose() {
    _sub?.cancel();
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
                      ? TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        )
                      : null,
                ),
                onTap: () => _mgr.playIndex(index),
                selected: active,
              );
            },
          ),
        ),
        // Shuffle / repeat
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  Icons.shuffle,
                  color: shuffleOn ? theme.colorScheme.primary : null,
                ),
                onPressed: () {
                  _mgr.toggleShuffle();
                  _shuffle.value = _mgr.shuffle;
                },
              ),
              IconButton(
                icon: Icon(
                  Icons.repeat,
                  color: repeatOn ? theme.colorScheme.primary : null,
                ),
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
