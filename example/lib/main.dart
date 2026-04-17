import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterCacheVideoPlayer.instance.initialize();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cache Video Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class _DemoItem {
  final String title;
  final String url;
  const _DemoItem(this.title, this.url);
}

const List<_DemoItem> _demoPlaylist = <_DemoItem>[
  _DemoItem(
    'Pexels · Portrait 1080p',
    'https://videos.pexels.com/video-files/33538187/14261042_1080_1920_60fps.mp4',
  ),
  _DemoItem(
    'Pexels · 4K Landscape',
    'https://videos.pexels.com/video-files/29603233/12740435_3840_2160_30fps.mp4',
  ),
  _DemoItem(
    'Flutter · Butterfly',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
  ),
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cache Video Player')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _demoPlaylist.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _demoPlaylist[index];
          return ListTile(
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text(item.title),
            subtitle: Text(
              item.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerPage(initialIndex: index),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final int initialIndex;
  const PlayerPage({super.key, required this.initialIndex});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final FlutterCacheVideoPlayerController _controller =
      FlutterCacheVideoPlayerController();
  late int _index = widget.initialIndex;
  bool _ready = false;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _controller.initialize();
    if (!mounted) return;
    setState(() => _ready = true);
    // Always start from the beginning when opening the demo.
    await _openCurrent();
    await _controller.play();
  }

  Future<void> _openCurrent({bool resumeHistory = false}) async {
    final item = _demoPlaylist[_index];
    await _controller.open(item.url, resumeHistory: resumeHistory);
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _demoPlaylist.length) return;
    setState(() => _index = index);
    await _openCurrent();
    await _controller.play();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (_fullscreen) {
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreen) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (!mounted) return;
    setState(() => _fullscreen = !_fullscreen);
  }

  void _showMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _SpeedRow(controller: _controller),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.skip_previous),
                title: const Text('Previous'),
                enabled: _index > 0,
                onTap: () {
                  Navigator.pop(ctx);
                  _playAt(_index - 1);
                },
              ),
              ListTile(
                leading: const Icon(Icons.skip_next),
                title: const Text('Next'),
                enabled: _index < _demoPlaylist.length - 1,
                onTap: () {
                  Navigator.pop(ctx);
                  _playAt(_index + 1);
                },
              ),
              ListTile(
                leading: Icon(
                  _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
                title: Text(
                  _fullscreen ? 'Exit fullscreen' : 'Enter fullscreen',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _toggleFullscreen();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = !_ready
        ? const ColoredBox(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          )
        : DefaultVideoPlayer(
            controller: _controller,
            aspectRatio: 16 / 9,
            fill: _fullscreen,
            onClose: () {
              if (_fullscreen) {
                _toggleFullscreen();
              } else {
                Navigator.of(context).maybePop();
              }
            },
            onMore: _showMoreSheet,
            topBarActions: <Widget>[
              PlayerIconButton(
                icon: _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                size: 22,
                onPressed: _toggleFullscreen,
                semanticsLabel: 'Toggle fullscreen',
              ),
            ],
          );

    if (_fullscreen) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: player),
      );
    }

    final current = _demoPlaylist[_index];
    return Scaffold(
      appBar: AppBar(title: Text(current.title)),
      body: Column(
        children: <Widget>[
          player,
          _PlayerStateBar(controller: _controller),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: _demoPlaylist.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = _demoPlaylist[i];
                final selected = i == _index;
                return ListTile(
                  selected: selected,
                  leading: Icon(
                    selected
                        ? Icons.play_arrow_rounded
                        : Icons.music_video_outlined,
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    item.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _playAt(i),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerStateBar extends StatelessWidget {
  final FlutterCacheVideoPlayerController controller;
  const _PlayerStateBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Watch.builder(
        builder: (context) {
          final state = controller.playState.value;
          final buffering = controller.isBuffering.value;
          final speed = controller.speed.value;
          final mime = controller.mimeType.value ?? '—';
          return Row(
            children: <Widget>[
              _Chip(label: 'State: ${state.name}'),
              const SizedBox(width: 8),
              _Chip(label: buffering ? 'Buffering' : 'Idle'),
              const SizedBox(width: 8),
              _Chip(label: '${speed}x'),
              const Spacer(),
              Text(mime, style: Theme.of(context).textTheme.bodySmall),
            ],
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: cs.onSecondaryContainer, fontSize: 12),
      ),
    );
  }
}

class _SpeedRow extends StatelessWidget {
  final FlutterCacheVideoPlayerController controller;
  const _SpeedRow({required this.controller});

  static const List<double> _speeds = <double>[0.5, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Watch.builder(
        builder: (context) {
          final current = controller.speed.value;
          return Row(
            children: <Widget>[
              const Text('Speed'),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: _speeds.map((s) {
                    final selected = (s - current).abs() < 0.01;
                    return ChoiceChip(
                      label: Text('${s}x'),
                      selected: selected,
                      onSelected: (_) => controller.setSpeed(s),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
