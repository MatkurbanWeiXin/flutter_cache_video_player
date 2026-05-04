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
        _videoElement?.play().toDart.catchError((_) {
          _sendEvent('playing', false);
          _sendEvent('buffering', false);
          return null;
        });
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
      case 'takeSnapshot':
        return _takeSnapshot();
      case 'extractCovers':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        return _extractCovers(args);
      case 'getDuration':
        final args = Map<String, dynamic>.from(call.arguments as Map);
        return _getDuration(args);
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
        final vw = video.videoWidth;
        final vh = video.videoHeight;
        if (vw > 0 && vh > 0) {
          _sendEvent('videoSize', {'width': vw, 'height': vh});
        }
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
    _sendEvent('playing', false);
    _sendEvent('buffering', true);
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

  /// 截取当前 `<video>` 画面为 PNG，返回 data URL（`data:image/png;base64,...`）。
  /// 如果跨域阻止读取（canvas tainted），则返回 null。
  ///
  /// Capture the current `<video>` frame as a PNG data URL. Returns null if
  /// the canvas is tainted due to cross-origin restrictions.
  String? _takeSnapshot() {
    final video = _videoElement;
    if (video == null) return null;
    try {
      final w = video.videoWidth == 0 ? 640 : video.videoWidth;
      final h = video.videoHeight == 0 ? 360 : video.videoHeight;
      final canvas = html.HTMLCanvasElement()
        ..width = w
        ..height = h;
      final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D?;
      if (ctx == null) return null;
      ctx.drawImage(video, 0, 0, w.toDouble(), h.toDouble());
      return canvas.toDataURL('image/png');
    } catch (_) {
      return null;
    }
  }

  /// 在 Web 上使用离屏 `<video>` 元素抽取候选封面帧，返回 data URL 列表。
  ///
  /// On Web, extract cover candidates with an offscreen `<video>`. Each frame
  /// `path` field is a `data:` URL; caller stores it in an [XFile].
  Future<List<Map<String, dynamic>>> _extractCovers(Map<String, dynamic> args) async {
    final url = args['url'] as String? ?? '';
    final count = (args['count'] as int?) ?? 5;
    final candidates = (args['candidates'] as int?) ?? (count * 3);
    final minBrightness = (args['minBrightness'] as num?)?.toDouble() ?? 0.08;
    if (url.isEmpty) return const [];

    final video = html.HTMLVideoElement()
      ..crossOrigin = 'anonymous'
      ..muted = true
      ..preload = 'auto'
      ..src = url;
    try {
      await video.onLoadedMetadata.first.timeout(const Duration(seconds: 15));
    } catch (_) {
      return const [];
    }
    final durationSec = video.duration;
    if (!durationSec.isFinite || durationSec <= 0) return const [];

    final lower = durationSec * 0.05;
    final upper = durationSec * 0.95;
    final span = (upper - lower).clamp(0.1, double.infinity);
    final n = candidates > count ? candidates : count;

    final frames = <Map<String, dynamic>>[];
    final canvas = html.HTMLCanvasElement();
    for (var i = 0; i < n; i++) {
      final t = lower + span * (i + 0.5) / n;
      video.currentTime = t;
      try {
        await video.onSeeked.first.timeout(const Duration(seconds: 5));
      } catch (_) {
        continue;
      }
      final w = video.videoWidth == 0 ? 640 : video.videoWidth;
      final h = video.videoHeight == 0 ? 360 : video.videoHeight;
      canvas
        ..width = w
        ..height = h;
      final ctx = canvas.getContext('2d') as html.CanvasRenderingContext2D?;
      if (ctx == null) continue;
      try {
        ctx.drawImage(video, 0, 0, w.toDouble(), h.toDouble());
        final brightness = _canvasAverageBrightness(ctx, w, h);
        if (brightness < minBrightness) continue;
        final dataUrl = canvas.toDataURL('image/png');
        frames.add({'path': dataUrl, 'positionMs': (t * 1000).toInt(), 'brightness': brightness});
      } catch (_) {
        // CORS / taint — abort; nothing we can read back.
        return const [];
      }
    }
    frames.sort(
      (a, b) =>
          ((b['brightness'] as num).toDouble()).compareTo((a['brightness'] as num).toDouble()),
    );
    return frames.take(count).toList();
  }

  /// 使用离屏 `<video>` 元素仅加载媒体元数据以获取精确时长（毫秒）。
  /// CORS 失败 / 超时 / `duration` 非有限值时返回 `null`。
  ///
  /// Probe accurate media duration (milliseconds) using a detached offscreen
  /// `<video>` element with `preload=metadata`. Returns `null` on CORS
  /// failure, timeout, or non-finite duration (HLS / live streams).
  Future<int?> _getDuration(Map<String, dynamic> args) async {
    final url = args['url'] as String? ?? '';
    final timeoutMs = (args['timeoutMs'] as int?) ?? 15000;
    if (url.isEmpty) return null;

    final video = html.HTMLVideoElement()
      ..crossOrigin = 'anonymous'
      ..muted = true
      ..preload = 'metadata'
      ..src = url;
    try {
      await video.onLoadedMetadata.first.timeout(Duration(milliseconds: timeoutMs));
    } catch (_) {
      try {
        video.removeAttribute('src');
      } catch (_) {}
      return null;
    }
    try {
      final seconds = video.duration;
      if (!seconds.isFinite || seconds <= 0) return null;
      return (seconds * 1000).toInt();
    } finally {
      try {
        video.removeAttribute('src');
      } catch (_) {}
    }
  }

  double _canvasAverageBrightness(html.CanvasRenderingContext2D ctx, int width, int height) {
    // Sample a downscaled region to keep work bounded; we re-draw on a
    // temp canvas to 64x64 then read imageData.
    const sw = 64;
    const sh = 64;
    final tmp = html.HTMLCanvasElement()
      ..width = sw
      ..height = sh;
    final tctx = tmp.getContext('2d') as html.CanvasRenderingContext2D?;
    if (tctx == null) return 0;
    tctx.drawImage(
      ctx.canvas,
      0,
      0,
      width.toDouble(),
      height.toDouble(),
      0,
      0,
      sw.toDouble(),
      sh.toDouble(),
    );
    final imageData = tctx.getImageData(0, 0, sw, sh);
    final data = imageData.data.toDart;
    var total = 0.0;
    for (var i = 0; i < data.length; i += 4) {
      final r = data[i] / 255.0;
      final g = data[i + 1] / 255.0;
      final b = data[i + 2] / 255.0;
      total += 0.299 * r + 0.587 * g + 0.114 * b;
    }
    final pixels = sw * sh;
    return total / pixels;
  }
}
