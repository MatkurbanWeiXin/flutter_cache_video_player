import 'dart:async';
import 'package:flutter/services.dart';
import 'package:signals/signals.dart';
import '../core/logger.dart';

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

  /// 原生纹理 ID，用于 Flutter Texture widget 渲染。
  /// Native texture ID for Flutter Texture widget rendering.
  int? get textureId => _textureId;

  /// 创建原生播放器实例并注册纹理，返回 Flutter Texture ID。
  /// Creates a native player instance, registers a texture, and returns the Flutter Texture ID.
  Future<int> create() async {
    _textureId = await _methodChannel.invokeMethod<int>('create');
    Logger.info('Native player created, textureId=$_textureId');
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
            Logger.error('EventChannel error: $error');
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
        Logger.error('Native player error: $message');
        errorSignal.set(message, force: true);
      case 'completed':
        completedSignal.set(completedSignal.value + 1, force: true);
      default:
        Logger.warning('Unknown native event: $type');
    }
  }

  /// 打开媒体 URL 进行播放。
  /// Opens the media URL for playback.
  Future<void> open(String url) async {
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
    } catch (e) {
      Logger.error('Error disposing native player: $e');
    }
    _textureId = null;
  }
}
