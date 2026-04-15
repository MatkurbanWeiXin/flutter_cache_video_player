import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> with SignalsMixin {
  late final _app = FlutterCacheVideoPlayer();
  late final _ready = createSignal(false);
  late final _error = createSignal<String?>(null);

  final FlutterSignal<List<String>> playList = signal([
    'https://videos.pexels.com/video-files/33538187/14261042_1080_1920_60fps.mp4',
    'https://videos.pexels.com/video-files/29603233/12740435_3840_2160_30fps.mp4',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
  ]);

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    try {
      FlutterCacheVideoPlayer.instance.initialize();
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

    Widget home;
    if (error != null) {
      home = Scaffold(
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
    } else if (!ready) {
      home = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else {
      home = SizedBox();
    }

    return MaterialApp(
      title: 'Cache Video Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      home: home,
    );
  }
}
