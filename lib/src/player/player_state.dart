import 'package:flutter/foundation.dart';

/// 播放状态枚举。
/// Playback state enumeration.
enum PlayState { idle, loading, playing, paused, stopped, error }

/// 响应式播放器状态，基于 ChangeNotifier 区动 UI 更新。
/// Reactive player state based on ChangeNotifier for driving UI updates.
class PlayerState extends ChangeNotifier {
  PlayState _playState = PlayState.idle;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  double _speed = 1.0;
  bool _isBuffering = false;
  String? _errorMessage;
  String? _currentUrl;
  String? _mimeType;

  PlayState get playState => _playState;
  Duration get position => _position;
  Duration get duration => _duration;
  double get volume => _volume;
  double get speed => _speed;
  bool get isBuffering => _isBuffering;
  String? get errorMessage => _errorMessage;
  String? get currentUrl => _currentUrl;
  String? get mimeType => _mimeType;
  bool get isVideo => _mimeType?.startsWith('video/') ?? false;
  bool get isAudio => _mimeType?.startsWith('audio/') ?? false;
  bool get isPlaying => _playState == PlayState.playing;

  double get progressPercent {
    if (_duration.inMilliseconds == 0) return 0;
    return _position.inMilliseconds / _duration.inMilliseconds;
  }

  /// 设置播放状态。
  /// Sets the current playback state.
  void setPlayState(PlayState state) {
    if (_playState == state) return;
    _playState = state;
    notifyListeners();
  }

  /// 设置当前播放位置。
  /// Sets the current playback position.
  void setPosition(Duration pos) {
    if (_position == pos) return;
    _position = pos;
    notifyListeners();
  }

  /// 设置媒体总时长。
  /// Sets the media total duration.
  void setDuration(Duration dur) {
    if (_duration == dur) return;
    _duration = dur;
    notifyListeners();
  }

  /// 设置音量（0.0 ~ 1.0）。
  /// Sets the volume (0.0 – 1.0).
  void setVolume(double vol) {
    final clamped = vol.clamp(0.0, 1.0);
    if (_volume == clamped) return;
    _volume = clamped;
    notifyListeners();
  }

  /// 设置播放速度。
  /// Sets the playback speed.
  void setSpeed(double spd) {
    if (_speed == spd) return;
    _speed = spd;
    notifyListeners();
  }

  /// 设置缓冲状态。
  /// Sets the buffering state.
  void setBuffering(bool buffering) {
    if (_isBuffering == buffering) return;
    _isBuffering = buffering;
    notifyListeners();
  }

  /// 设置错误消息。
  /// Sets the error message.
  void setError(String? message) {
    if (_errorMessage == message && (message == null || _playState == PlayState.error)) return;
    _errorMessage = message;
    if (message != null) _playState = PlayState.error;
    notifyListeners();
  }

  /// 设置当前播放的 URL。
  /// Sets the currently playing URL.
  void setCurrentUrl(String? url) {
    if (_currentUrl == url) return;
    _currentUrl = url;
    notifyListeners();
  }

  /// 设置媒体 MIME 类型。
  /// Sets the media MIME type.
  void setMimeType(String? mime) {
    if (_mimeType == mime) return;
    _mimeType = mime;
    notifyListeners();
  }

  /// 重置所有状态为初始值。
  /// Resets all state to initial values.
  void reset() {
    _playState = PlayState.idle;
    _position = Duration.zero;
    _duration = Duration.zero;
    _isBuffering = false;
    _errorMessage = null;
    _currentUrl = null;
    _mimeType = null;
    notifyListeners();
  }
}
