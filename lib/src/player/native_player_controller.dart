import 'dart:async';
import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// 原生播放器控制器，通过 MethodChannel 和 EventChannel 与各平台原生播放器通信。
/// Native player controller communicating with platform-specific players via MethodChannel and EventChannel.
class NativePlayerController {
  static const _methodChannel = MethodChannel('flutter_cache_video_player/player');
  static const _eventChannel = EventChannel('flutter_cache_video_player/player/events');

  int? _textureId;
  StreamSubscription? _eventSubscription;

  final positionSignal = signal(Duration.zero);

  final durationSignal = signal(Duration.zero);

  final playingSignal = signal(false);

  final bufferingSignal = signal(false);

  final errorSignal = signal<String?>(null);

  final completedSignal = signal(0);

  /// 视频原始分辨率（已考虑显示方向 / 像素比）；尚未知时为 `Size.zero`。
  /// Natural video size (already accounting for display rotation / pixel
  /// aspect ratio). `Size.zero` until reported by the native player.
  final videoSizeSignal = signal<Size>(Size.zero);

  /// 原生纹理 ID，用于 Flutter Texture widget 渲染。
  /// Native texture ID for Flutter Texture widget rendering.
  int? get textureId => _textureId;

  /// 创建原生播放器实例并注册纹理，返回 Flutter Texture ID。
  /// Creates a native player instance, registers a texture, and returns the Flutter Texture ID.
  Future<int> create() async {
    _textureId = await _methodChannel.invokeMethod<int>('create');
    _listenEvents();
    return _textureId!;
  }

  void _listenEvents() {
    _eventSubscription = _eventChannel
        .receiveBroadcastStream()
        .map((e) => Map<String, dynamic>.from(e as Map))
        .listen(
          _handleEvent,
          onError: (error) {
            errorSignal.set(error.toString(), force: true);
          },
        );
  }

  void _handleEvent(Map<String, dynamic> event) {
    final type = event['event'] as String?;
    switch (type) {
      case 'position':
        final ms = event['value'] as int;
        positionSignal.value = Duration(milliseconds: ms);
      case 'duration':
        final ms = event['value'] as int;
        durationSignal.value = Duration(milliseconds: ms);
      case 'playing':
        final playing = event['value'] as bool;
        playingSignal.value = playing;
      case 'buffering':
        final buffering = event['value'] as bool;
        bufferingSignal.value = buffering;
      case 'error':
        final message = event['value'] as String;
        errorSignal.set(message, force: true);
      case 'completed':
        completedSignal.set(completedSignal.value + 1, force: true);
      case 'videoSize':
        final value = event['value'];
        if (value is Map) {
          final w = (value['width'] as num?)?.toDouble() ?? 0;
          final h = (value['height'] as num?)?.toDouble() ?? 0;
          if (w > 0 && h > 0) {
            videoSizeSignal.value = Size(w, h);
          } else {
            videoSizeSignal.value = Size.zero;
          }
        }
      default:
    }
  }

  /// 打开媒体 URL 进行播放。
  /// Opens the media URL for playback.
  Future<void> open(String url) async {
    // 重置所有信号到初始值，确保原生端发送的新事件（如 playing: true）
    // 产生真正的值变化，从而触发 effect。否则当上一个视频仍在播放时
    // 切换视频，playingSignal 始终为 true，signal 库判定无变化不通知。
    // Reset all signals so that events from the new native session produce
    // real value changes. Without this, switching while playing leaves
    // playingSignal == true, and the native "playing: true" becomes a no-op.
    positionSignal.value = Duration.zero;
    durationSignal.value = Duration.zero;
    playingSignal.value = false;
    bufferingSignal.value = false;
    errorSignal.value = null;
    videoSizeSignal.value = Size.zero;
    await _methodChannel.invokeMethod('open', {'url': url});
  }

  /// 开始播放。
  /// Starts playback.
  Future<void> play() async {
    await _methodChannel.invokeMethod('play');
  }

  /// 暂停播放。
  /// Pauses playback.
  Future<void> pause() async {
    await _methodChannel.invokeMethod('pause');
  }

  /// 跳转到指定位置（毫秒）。
  /// Seeks to the specified position in milliseconds.
  Future<void> seek(int positionMs) async {
    await _methodChannel.invokeMethod('seek', {'position': positionMs});
  }

  /// 设置音量（0.0 ~ 1.0）。
  /// Sets the volume (0.0 – 1.0).
  Future<void> setVolume(double volume) async {
    await _methodChannel.invokeMethod('setVolume', {'volume': volume.clamp(0.0, 1.0)});
  }

  /// 设置播放速度。
  /// Sets the playback speed.
  Future<void> setSpeed(double speed) async {
    await _methodChannel.invokeMethod('setSpeed', {'speed': speed});
  }

  /// 释放原生播放器资源。
  /// Disposes the native player resources.
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (_) {}
    _textureId = null;
  }

  /// 截取当前播放画面，返回 PNG [XFile]。
  /// Snapshot the current frame as a PNG [XFile].
  Future<XFile> takeSnapshot({String? savePath}) async {
    final raw = await _methodChannel.invokeMethod<dynamic>('takeSnapshot');
    if (raw == null) {
      throw StateError('Native player returned no snapshot data.');
    }
    if (kIsWeb) {
      // Web returns either a data URL string or a Uint8List.
      if (raw is String) {
        return XFile(raw, mimeType: 'image/png');
      }
      final bytes = _asUint8List(raw);
      return XFile.fromData(bytes, mimeType: 'image/png', name: _defaultSnapshotName());
    }
    final bytes = _asUint8List(raw);
    final outPath = savePath ?? await _defaultSnapshotPath();
    final file = File(outPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return XFile(outPath, mimeType: 'image/png');
  }

  /// 调用原生 `extractCovers`，返回 [{positionMs, brightness, path}] 列表。
  /// Invokes the native `extractCovers` and returns the raw list of
  /// `{positionMs, brightness, path}` maps.
  Future<List<Map<String, dynamic>>> invokeExtractCovers({
    required String url,
    required int count,
    required int candidateCount,
    required double minBrightness,
    required String outputDir,
  }) async {
    final raw = await _methodChannel.invokeMethod<dynamic>('extractCovers', {
      'url': url,
      'count': count,
      'candidates': candidateCount,
      'minBrightness': minBrightness,
      'outputDir': outputDir,
    });
    if (raw == null) return const <Map<String, dynamic>>[];
    final list = (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return list;
  }

  static Uint8List _asUint8List(dynamic raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    throw StateError('Unsupported snapshot payload: ${raw.runtimeType}');
  }

  static String _defaultSnapshotName() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'snapshot-$ts.png';
  }

  static Future<String> _defaultSnapshotPath() async {
    final dir = await getTemporaryDirectory();
    final name = _defaultSnapshotName();
    return '${dir.path}/flutter_cache_video_player/snapshots/$name';
  }
}
