import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_video_player/src/data/enums/play_state.dart';
import 'package:flutter_cache_video_player/src/player/native_player_controller.dart';
import 'package:flutter_cache_video_player/src/player/video_player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoPlayerController', () {
    late Directory tempDir;
    late File mediaFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fcvp-controller-test-');
      mediaFile = File('${tempDir.path}/sample.mp4');
      await mediaFile.writeAsBytes(List<int>.filled(32, 7), flush: true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('openFile leaves loading when duration arrives before playing', (tester) async {
      final nativeController = _FakeNativePlayerController();
      final controller = VideoPlayerController(nativeController: nativeController);

      await controller.initialize();
      await controller.openFile(mediaFile.path);

      expect(controller.playState.value, PlayState.loading);

      nativeController.emitDuration(const Duration(seconds: 5));
      await tester.pump();

      expect(controller.playState.value, PlayState.paused);
      expect(controller.duration.value, const Duration(seconds: 5));
      expect(controller.isBuffering.value, isFalse);

      await controller.dispose();
    });

    testWidgets('openFile leaves loading when video size arrives before duration', (tester) async {
      final nativeController = _FakeNativePlayerController();
      final controller = VideoPlayerController(nativeController: nativeController);

      await controller.initialize();
      await controller.openFile(mediaFile.path);

      expect(controller.playState.value, PlayState.loading);

      nativeController.emitVideoSize(const Size(640, 360));
      await tester.pump();

      expect(controller.playState.value, PlayState.paused);
      expect(controller.videoSize.value, const Size(640, 360));

      await controller.dispose();
    });

    testWidgets('playFile opens and starts playback', (tester) async {
      final nativeController = _FakeNativePlayerController();
      final controller = VideoPlayerController(nativeController: nativeController);

      await controller.initialize();
      await controller.playFile(mediaFile.path);

      await tester.pump();
      expect(controller.playState.value, PlayState.playing);

      nativeController.emitDuration(const Duration(seconds: 8));
      nativeController.emitPosition(const Duration(seconds: 2));
      await tester.pump();

      expect(controller.playState.value, PlayState.playing);
      expect(controller.duration.value, const Duration(seconds: 8));
      expect(controller.position.value, const Duration(seconds: 2));

      await controller.dispose();
    });

    testWidgets('keeps stopped state when the native player later reports paused', (tester) async {
      final nativeController = _FakeNativePlayerController();
      final controller = VideoPlayerController(nativeController: nativeController);

      await controller.initialize();
      await controller.playFile(mediaFile.path);

      nativeController.emitDuration(const Duration(seconds: 6));
      nativeController.emitPlaying(true);
      nativeController.emitPosition(const Duration(seconds: 1));
      await tester.pump();

      await controller.stop();
      nativeController.emitPlaying(false);
      await tester.pump();

      expect(controller.playState.value, PlayState.stopped);

      await controller.dispose();
    });

    testWidgets('cachedProgress is the primary cache-progress signal', (tester) async {
      final nativeController = _FakeNativePlayerController();
      final controller = VideoPlayerController(nativeController: nativeController);

      await controller.initialize();
      await controller.openFile(mediaFile.path);
      await tester.pump();

      expect(controller.cachedProgress.value, 1.0);
      expect(controller.bufferedProgress.value, controller.cachedProgress.value);

      await controller.dispose();
    });
  });
}

class _FakeNativePlayerController extends NativePlayerController {
  String? lastOpenedUrl;

  @override
  Future<int> create() async => 1;

  @override
  Future<void> open(String url) async {
    lastOpenedUrl = url;
    positionSignal.value = Duration.zero;
    durationSignal.value = Duration.zero;
    playingSignal.value = false;
    bufferingSignal.value = false;
    errorSignal.value = null;
    videoSizeSignal.value = Size.zero;
  }

  @override
  Future<void> play() async {
    playingSignal.value = true;
  }

  @override
  Future<void> pause() async {
    playingSignal.value = false;
  }

  @override
  Future<void> seek(int positionMs) async {
    positionSignal.value = Duration(milliseconds: positionMs);
  }

  @override
  Future<void> dispose() async {}

  void emitDuration(Duration value) {
    durationSignal.value = value;
  }

  void emitPlaying(bool value) {
    playingSignal.value = value;
  }

  void emitPosition(Duration value) {
    positionSignal.value = value;
  }

  void emitVideoSize(Size value) {
    videoSizeSignal.value = value;
  }
}
