import 'dart:async';
import 'dart:js_interop';

import 'dart:ui_web' as ui_web;

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as html;

/// Web 平台视频播放器插件实现，基于 HTML5 <video> 元素。
/// Web platform video player plugin implementation using HTML5 <video> element.
class FlutterCacheVideoPlayerWeb {
  html.HTMLVideoElement? _videoElement;
  Timer? _positionTimer;
  final _eventController = StreamController<dynamic>.broadcast();
  bool _viewRegistered = false;

  /// 注册 Web 插件。 / Registers the web plugin.
  static void registerWith(Registrar registrar) {
    final instance = FlutterCacheVideoPlayerWeb();

    final methodChannel = MethodChannel(
      'flutter_cache_video_player/player',
      const StandardMethodCodec(),
      registrar,
    );
    methodChannel.setMethodCallHandler(instance._handleMethodCall);

    // ignore: deprecated_member_use
    final eventChannel = PluginEventChannel<dynamic>(
      'flutter_cache_video_player/player/events',
      const StandardMethodCodec(),
      registrar,
    );
    eventChannel.setController(instance._eventController);
  }

  void _sendEvent(String name, dynamic value) {
    _eventController.add(<String, dynamic>{'event': name, 'value': value});
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'create':
        return _create();
      case 'open':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        _open(args['url'] as String);
        return null;
      case 'play':
        _videoElement?.play();
        return null;
      case 'pause':
        _videoElement?.pause();
        return null;
      case 'seek':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final ms = args['position'] as int;
        if (_videoElement != null) {
          _videoElement!.currentTime = ms / 1000.0;
        }
        return null;
      case 'setVolume':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final vol = (args['volume'] as num).toDouble();
        if (_videoElement != null) _videoElement!.volume = vol;
        return null;
      case 'setSpeed':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final speed = (args['speed'] as num).toDouble();
        if (_videoElement != null) _videoElement!.playbackRate = speed;
        return null;
      case 'dispose':
        _dispose();
        return null;
      case 'getPlatformVersion':
        return 'Web';
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: '${call.method} not implemented on web',
        );
    }
  }

  int _create() {
    _videoElement = html.HTMLVideoElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.setProperty('object-fit', 'contain')
      ..style.backgroundColor = 'black'
      ..autoplay = false;

    if (!_viewRegistered) {
      ui_web.platformViewRegistry.registerViewFactory(
        'flutter-cache-video-player-web',
        (int viewId) => _videoElement!,
      );
      _viewRegistered = true;
    }

    _setupListeners();
    return 0;
  }

  void _setupListeners() {
    final video = _videoElement!;

    video.addEventListener(
      'loadedmetadata',
      ((html.Event e) {
        final durationMs = (video.duration * 1000).toInt();
        _sendEvent('duration', durationMs);
        _sendEvent('buffering', false);
        // 如果视频未在自动播放，通知 Dart 转入 paused 状态（而非停留在 loading）。
        // If the video is not auto-playing, notify Dart to transition to paused (instead of staying in loading).
        if (video.paused) {
          _sendEvent('playing', false);
        }
      }).toJS,
    );

    video.addEventListener(
      'play',
      ((html.Event e) {
        _sendEvent('playing', true);
        _startPositionTimer();
      }).toJS,
    );

    video.addEventListener(
      'pause',
      ((html.Event e) {
        _sendEvent('playing', false);
        _stopPositionTimer();
      }).toJS,
    );

    video.addEventListener(
      'ended',
      ((html.Event e) {
        _sendEvent('completed', null);
        _stopPositionTimer();
      }).toJS,
    );

    video.addEventListener(
      'error',
      ((html.Event e) {
        _sendEvent('error', 'Video playback error');
      }).toJS,
    );

    video.addEventListener(
      'waiting',
      ((html.Event e) {
        _sendEvent('buffering', true);
      }).toJS,
    );

    video.addEventListener(
      'playing',
      ((html.Event e) {
        _sendEvent('buffering', false);
      }).toJS,
    );
  }

  void _open(String url) {
    _videoElement?.src = url;
    _videoElement?.load();
    _sendEvent('buffering', true);
    // 自动播放：load 后立即调用 play()，与 Android/Windows 原生端行为一致。
    // 浏览器自动播放策略可能拒绝，捕获异常后发送 playing(false) 让 Dart 转入 paused 状态。
    // Auto-play: call play() right after load(), matching Android/Windows native behavior.
    // Browser autoplay policy may reject; catch and send playing(false) so Dart transitions to paused.
    _videoElement?.play().toDart.catchError((_) {
      _sendEvent('playing', false);
      _sendEvent('buffering', false);
      return null;
    });
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_videoElement != null) {
        final ms = (_videoElement!.currentTime * 1000).toInt();
        _sendEvent('position', ms);
      }
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _dispose() {
    _stopPositionTimer();
    _videoElement?.pause();
    _videoElement?.removeAttribute('src');
    _videoElement = null;
  }
}
