import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterCacheVideoPlayer.instance.initialize();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cache Video Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData.light(useMaterial3: true).copyWith(
        extensions: const <ThemeExtension<dynamic>>[
          VideoPlayerTheme(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black,
          ),
        ],
      ),
      darkTheme: ThemeData.dark(useMaterial3: true).copyWith(
        extensions: const <ThemeExtension<dynamic>>[
          VideoPlayerTheme(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black,
          ),
        ],
      ),
      home: const HomePage(),
    );
  }

  @override
  void dispose() {
    FlutterCacheVideoPlayer.instance.dispose();
    super.dispose();
  }
}

class _DemoItem {
  final String title;
  final String url;

  const _DemoItem(this.title, this.url);
}

const List<_DemoItem> _demoPlaylist = <_DemoItem>[
  _DemoItem(
    'ce shi',
    'https://jsontodart.cn/api/object/7976982000/msg_video_dd802bb84715adfbbf71fa7413eb1d29.mp4',
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
  final VideoPlayerController _controller = VideoPlayerController();
  late int _index = widget.initialIndex;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _controller.initialize();
    if (!mounted) return;
    // Always start from the beginning when opening the demo.
    await _openCurrent();
  }

  Future<void> _openCurrent({bool resumeHistory = false}) async {
    final item = _demoPlaylist[_index];
    await _controller.playNetwork(item.url, resumeHistory: resumeHistory);
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _demoPlaylist.length) return;
    setState(() => _index = index);
    await _openCurrent();
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
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take snapshot (PNG)'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _takeSnapshot();
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Extract cover candidates'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _extractCovers();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _takeSnapshot() async {
    try {
      final xfile = await _controller.takeSnapshot();
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => _SnapshotDialog(file: xfile),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Snapshot failed: $e')));
    }
  }

  Future<void> _extractCovers() async {
    final item = _demoPlaylist[_index];
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Extracting covers...')),
    );
    try {
      final frames = await FlutterCacheVideoPlayer.instance
          .extractCoverCandidates(VideoSource.network(item.url), count: 5);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      if (frames.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No covers extracted.')),
        );
        return;
      }
      showDialog<void>(
        context: context,
        builder: (_) => _CoversDialog(frames: frames),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Cover extraction failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!mounted) return const SizedBox.shrink();
    Widget player;
    if (_fullscreen) {
      player = VideoPlayer(
        controller: _controller,
        fill: true,
        onClose: _toggleFullscreen,
        topBarActions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            color: Colors.white,
            onPressed: _showMoreSheet,
          ),
        ],
      );
    } else {
      player = AspectRatio(
        aspectRatio: 16 / 9,
        child: VideoPlayer(
          controller: _controller,
          fill: true,
          topBarActions: [
            IconButton(
              icon: const Icon(Icons.more_horiz),
              color: Colors.white,
              onPressed: _showMoreSheet,
            ),
          ],
          // no close button in inline mode for example
        ),
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
  final VideoPlayerController controller;

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
  final VideoPlayerController controller;

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

class _SnapshotDialog extends StatelessWidget {
  final XFile file;

  const _SnapshotDialog({required this.file});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Snapshot', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _imageFor(file),
            ),
            const SizedBox(height: 8),
            SelectableText(
              file.path,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoversDialog extends StatelessWidget {
  final List<VideoCoverFrame> frames;

  const _CoversDialog({required this.frames});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Cover candidates (${frames.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: frames.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final f = frames[i];
                  return Row(
                    children: <Widget>[
                      SizedBox(
                        width: 100,
                        height: 56,
                        child: _imageFor(f.image, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Pos: ${f.position.inMilliseconds}ms',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              'Brightness: ${f.brightness.toStringAsFixed(3)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _imageFor(XFile file, {BoxFit fit = BoxFit.contain}) {
  if (kIsWeb) {
    // On web, path is a data: or blob: URL.
    return Image.network(file.path, fit: fit);
  }
  return Image.file(File(file.path), fit: fit);
}
