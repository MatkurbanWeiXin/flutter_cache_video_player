import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/play_state.dart';
import '../player/flutter_cache_video_player_controller.dart';
import 'flutter_cache_video_player_view.dart';
import 'style/default_video_player_style.dart';
import 'widgets/player_gradient_mask.dart';
import 'widgets/player_icon_button.dart';
import 'widgets/player_scrubber_slider.dart';

/// 传递给自定义槽位 builder 的上下文，提供控制器和当前样式。
/// Context passed to slot builders so callers can reuse controller and style.
class DefaultVideoPlayerSlotContext {
  final FlutterCacheVideoPlayerController controller;
  final DefaultVideoPlayerStyle style;
  final VoidCallback showControls;
  final VoidCallback hideControls;

  const DefaultVideoPlayerSlotContext({
    required this.controller,
    required this.style,
    required this.showControls,
    required this.hideControls,
  });
}

/// 高性能的默认视频播放器组件。
///
/// 在 [FlutterCacheVideoPlayerView] 的视频画面之上叠加顶部栏、中央控制按钮和
/// 底部进度条。点击画面可平滑切换控件显隐，播放中自动隐藏。
///
/// Drop-in default video player. Renders the native video frame via
/// [FlutterCacheVideoPlayerView] and overlays a polished, iOS-style control
/// surface: a top bar with "done" + more, center transport controls, and a
/// thin bottom scrubber with buffered progress. Tapping the frame fades the
/// controls in/out and they auto-hide during playback.
class DefaultVideoPlayer extends StatefulWidget {
  /// 底层播放控制器。
  /// The underlying player controller.
  final FlutterCacheVideoPlayerController controller;

  /// 视频宽高比。当 [fill] 为 true 时此属性被忽略，播放器会铺满外部约束。
  /// Aspect ratio used when [fill] is false.
  final double aspectRatio;

  /// 是否铺满父约束（常用于全屏容器或 SizedBox.expand）。
  /// When true the player fills the available space instead of using aspect ratio.
  final bool fill;

  /// 快退/快进时间（默认 10 秒）。
  /// Skip duration for the rewind / fast-forward buttons (default: 10 s).
  final Duration skipDuration;

  /// 播放中自动隐藏控件的延时。设为 [Duration.zero] 可关闭自动隐藏。
  /// Auto-hide delay while playing. Use [Duration.zero] to disable.
  final Duration autoHideDelay;

  /// 控件淡入淡出时长。
  /// Fade-in / fade-out duration of the overlay controls.
  final Duration fadeDuration;

  /// 初始是否显示控件。
  /// Whether the overlay is visible when the widget first mounts.
  final bool initiallyVisible;

  /// 外部提供的已缓存进度（0.0 – 1.0），用于覆盖默认的插件内置进度。
  /// 不提供时，进度条会自动使用 [FlutterCacheVideoPlayerController.bufferedProgress]
  /// （由插件的缓存位图驱动）。
  ///
  /// Optional override for the cached-progress signal. When omitted the
  /// scrubber automatically reflects
  /// [FlutterCacheVideoPlayerController.bufferedProgress], which the plugin
  /// drives from the download bitmap in its cache repository.
  final ValueListenable<double>? bufferedProgress;

  /// 视觉样式。
  /// Visual style bundle.
  final DefaultVideoPlayerStyle style;

  /// 点击左上角"完成/收起"按钮。为 null 时尝试 `Navigator.maybePop`。
  /// Handler for the leading "done" button. Falls back to `Navigator.maybePop`.
  final VoidCallback? onClose;

  /// 点击右上角"更多"按钮。
  /// Handler for the trailing "more" (ellipsis) button.
  final VoidCallback? onMore;

  /// 顶部栏右侧在"更多"按钮前面插入的额外 actions（例如画中画、投屏）。
  /// Extra trailing actions rendered before the "more" ellipsis.
  final List<Widget> topBarActions;

  /// 自定义错误视图。
  /// Custom error builder forwarded to [FlutterCacheVideoPlayerView].
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;

  /// 自定义加载视图。
  /// Custom loading builder forwarded to [FlutterCacheVideoPlayerView].
  final Widget Function(BuildContext context)? loadingBuilder;

  /// 完全自定义顶部栏（返回的 widget 将取代默认顶部栏）。
  /// Override for the entire top bar.
  final Widget Function(BuildContext, DefaultVideoPlayerSlotContext)? topBarBuilder;

  /// 完全自定义中央控制区。
  /// Override for the center transport controls.
  final Widget Function(BuildContext, DefaultVideoPlayerSlotContext)? centerControlsBuilder;

  /// 完全自定义底部进度条行。
  /// Override for the bottom scrubber row.
  final Widget Function(BuildContext, DefaultVideoPlayerSlotContext)? bottomScrubberBuilder;

  /// 在默认覆盖层之后再叠加的自定义图层（例如弹幕、字幕）。
  /// Extra overlay rendered above the default controls (e.g. subtitles).
  final Widget Function(BuildContext, DefaultVideoPlayerSlotContext)? extraOverlayBuilder;

  const DefaultVideoPlayer({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
    this.fill = false,
    this.skipDuration = const Duration(seconds: 10),
    this.autoHideDelay = const Duration(seconds: 3),
    this.fadeDuration = const Duration(milliseconds: 240),
    this.initiallyVisible = true,
    this.bufferedProgress,
    this.style = const DefaultVideoPlayerStyle(),
    this.onClose,
    this.onMore,
    this.topBarActions = const <Widget>[],
    this.errorBuilder,
    this.loadingBuilder,
    this.topBarBuilder,
    this.centerControlsBuilder,
    this.bottomScrubberBuilder,
    this.extraOverlayBuilder,
  });

  @override
  State<DefaultVideoPlayer> createState() => _DefaultVideoPlayerState();
}

class _DefaultVideoPlayerState extends State<DefaultVideoPlayer> {
  late bool _visible = widget.initiallyVisible;
  Timer? _hideTimer;
  VoidCallback? _playingDisposer;

  @override
  void initState() {
    super.initState();
    _playingDisposer = effect(() {
      final playing = widget.controller.isPlaying.value;
      if (playing && _visible) {
        _scheduleAutoHide();
      } else if (!playing) {
        _hideTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingDisposer?.call();
    super.dispose();
  }

  void _showControls({bool scheduleAutoHide = true}) {
    _hideTimer?.cancel();
    if (!_visible) {
      setState(() => _visible = true);
    }
    if (scheduleAutoHide) {
      _scheduleAutoHide();
    }
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (_visible) {
      setState(() => _visible = false);
    }
  }

  void _toggleControls() {
    if (_visible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    if (widget.autoHideDelay == Duration.zero) return;
    if (!widget.controller.isPlaying.value) return;
    _hideTimer = Timer(widget.autoHideDelay, () {
      if (!mounted) return;
      if (widget.controller.isPlaying.value) {
        _hideControls();
      }
    });
  }

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  DefaultVideoPlayerSlotContext _slotContext() {
    return DefaultVideoPlayerSlotContext(
      controller: widget.controller,
      style: widget.style,
      showControls: _showControls,
      hideControls: _hideControls,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;

    final videoView = FlutterCacheVideoPlayerView(
      controller: widget.controller,
      aspectRatio: widget.aspectRatio,
      backgroundColor: style.backgroundColor,
      errorBuilder: widget.errorBuilder,
      loadingBuilder: widget.loadingBuilder,
    );

    // React to play-state changes to (re)arm the auto-hide timer.
    // See the effect registered in initState.

    final slot = _slotContext();

    final overlay = IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: widget.fadeDuration,
        curve: Curves.easeOut,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (style.enableGlassmorphism)
              BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: style.glassmorphismBlur,
                  sigmaY: style.glassmorphismBlur,
                ),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.08)),
              ),
            if (style.scrimIntensity > 0) PlayerGradientMask(intensity: style.scrimIntensity),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child:
                    widget.topBarBuilder?.call(context, slot) ??
                    _DefaultTopBar(
                      slot: slot,
                      onClose: _handleClose,
                      onMore: widget.onMore,
                      actions: widget.topBarActions,
                    ),
              ),
            ),
            Center(
              child:
                  widget.centerControlsBuilder?.call(context, slot) ??
                  _DefaultCenterControls(
                    slot: slot,
                    skipDuration: widget.skipDuration,
                    onInteract: _showControls,
                  ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child:
                    widget.bottomScrubberBuilder?.call(context, slot) ??
                    _DefaultBottomScrubber(
                      slot: slot,
                      bufferedProgress:
                          widget.bufferedProgress ?? widget.controller.bufferedProgress,
                      onInteractStart: () => _hideTimer?.cancel(),
                      onInteractEnd: _scheduleAutoHide,
                    ),
              ),
            ),
          ],
        ),
      ),
    );

    Widget stack = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(child: videoView),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(child: overlay),
        if (widget.extraOverlayBuilder != null)
          Positioned.fill(child: widget.extraOverlayBuilder!(context, slot)),
      ],
    );

    stack = ColoredBox(color: style.backgroundColor, child: stack);

    if (widget.fill) {
      return stack;
    }
    return AspectRatio(aspectRatio: widget.aspectRatio, child: stack);
  }
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------

class _DefaultTopBar extends StatelessWidget {
  final DefaultVideoPlayerSlotContext slot;
  final VoidCallback onClose;
  final VoidCallback? onMore;
  final List<Widget> actions;

  const _DefaultTopBar({
    required this.slot,
    required this.onClose,
    required this.onMore,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final style = slot.style;
    return Padding(
      padding: style.topBarPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          PlayerIconButton(
            icon: CupertinoIcons.clear,
            size: style.topBarIconSize,
            color: style.foregroundColor,
            onPressed: onClose,
            semanticsLabel: 'Close',
          ),
          const Spacer(),
          ...actions,
          PlayerIconButton(
            icon: CupertinoIcons.ellipsis,
            size: style.topBarIconSize,
            color: style.foregroundColor,
            onPressed: onMore,
            semanticsLabel: 'More options',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Center controls
// ---------------------------------------------------------------------------

class _DefaultCenterControls extends StatelessWidget {
  final DefaultVideoPlayerSlotContext slot;
  final Duration skipDuration;
  final VoidCallback onInteract;

  const _DefaultCenterControls({
    required this.slot,
    required this.skipDuration,
    required this.onInteract,
  });

  Future<void> _skipBy(Duration delta) async {
    final controller = slot.controller;
    final current = controller.position.value;
    final total = controller.duration.value;
    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (total > Duration.zero && target > total) target = total;
    await controller.seek(target);
    onInteract();
  }

  IconData _skipBackwardIcon(int seconds) {
    switch (seconds) {
      case 15:
        return CupertinoIcons.gobackward_15;
      case 30:
        return CupertinoIcons.gobackward_30;
      case 45:
        return CupertinoIcons.gobackward_45;
      case 60:
        return CupertinoIcons.gobackward_60;
      case 75:
        return CupertinoIcons.gobackward_75;
      case 90:
        return CupertinoIcons.gobackward_90;
      default:
        return CupertinoIcons.gobackward_10;
    }
  }

  IconData _skipForwardIcon(int seconds) {
    switch (seconds) {
      case 15:
        return CupertinoIcons.goforward_15;
      case 30:
        return CupertinoIcons.goforward_30;
      case 45:
        return CupertinoIcons.goforward_45;
      case 60:
        return CupertinoIcons.goforward_60;
      case 75:
        return CupertinoIcons.goforward_75;
      case 90:
        return CupertinoIcons.goforward_90;
      default:
        return CupertinoIcons.goforward_10;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = slot.style;
    final controller = slot.controller;
    final seconds = skipDuration.inSeconds;

    return Watch.builder(
      builder: (context) {
        final state = controller.playState.value;
        final buffering = controller.isBuffering.value;
        final isPlaying = state == PlayState.playing;
        final canInteract = state != PlayState.loading && state != PlayState.error;

        Widget centerButton;
        if (state == PlayState.loading || (buffering && !isPlaying)) {
          centerButton = SizedBox(
            width: style.centerPrimaryIconSize,
            height: style.centerPrimaryIconSize,
            child: CupertinoActivityIndicator(
              color: style.foregroundColor,
              radius: style.centerPrimaryIconSize / 3,
            ),
          );
        } else {
          centerButton = PlayerIconButton(
            icon: isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
            size: style.centerPrimaryIconSize,
            color: style.foregroundColor,
            onPressed: canInteract
                ? () {
                    controller.playOrPause();
                    onInteract();
                  }
                : null,
            semanticsLabel: isPlaying ? 'Pause' : 'Play',
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            PlayerIconButton(
              icon: _skipBackwardIcon(seconds),
              size: style.centerSecondaryIconSize,
              color: style.foregroundColor,
              onPressed: canInteract ? () => _skipBy(-skipDuration) : null,
              semanticsLabel: 'Rewind $seconds seconds',
            ),
            SizedBox(width: style.centerControlsSpacing),
            centerButton,
            SizedBox(width: style.centerControlsSpacing),
            PlayerIconButton(
              icon: _skipForwardIcon(seconds),
              size: style.centerSecondaryIconSize,
              color: style.foregroundColor,
              onPressed: canInteract ? () => _skipBy(skipDuration) : null,
              semanticsLabel: 'Forward $seconds seconds',
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom scrubber
// ---------------------------------------------------------------------------

class _DefaultBottomScrubber extends StatefulWidget {
  final DefaultVideoPlayerSlotContext slot;
  final ValueListenable<double>? bufferedProgress;
  final VoidCallback onInteractStart;
  final VoidCallback onInteractEnd;

  const _DefaultBottomScrubber({
    required this.slot,
    required this.bufferedProgress,
    required this.onInteractStart,
    required this.onInteractEnd,
  });

  @override
  State<_DefaultBottomScrubber> createState() => _DefaultBottomScrubberState();
}

class _DefaultBottomScrubberState extends State<_DefaultBottomScrubber> {
  double? _dragValue;

  String _formatDuration(Duration d, {bool negative = false}) {
    if (d.isNegative) d = Duration.zero;
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    final body = hours > 0
        ? '${two(hours)}:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
    return negative ? '-$body' : body;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.slot.style;
    final controller = widget.slot.controller;

    return Padding(
      padding: style.bottomBarPadding,
      child: Watch.builder(
        builder: (context) {
          final position = controller.position.value;
          final duration = controller.duration.value;
          final hasDuration = duration.inMilliseconds > 0;
          final progress = hasDuration
              ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
              : 0.0;
          final effectiveValue = _dragValue ?? progress;
          final previewDuration = Duration(
            milliseconds: (duration.inMilliseconds * effectiveValue).round(),
          );
          final remaining = hasDuration ? (duration - previewDuration) : Duration.zero;

          final scrubber = _BufferedScrubber(
            value: effectiveValue,
            bufferedProgress: widget.bufferedProgress,
            activeColor: style.scrubberActiveColor,
            bufferedColor: style.scrubberBufferedColor,
            inactiveColor: style.scrubberInactiveColor,
            trackHeight: style.scrubberTrackHeight,
            activeTrackHeight: style.scrubberActiveTrackHeight,
            thumbRadius: style.scrubberThumbRadius,
            activeThumbRadius: style.scrubberActiveThumbRadius,
            onChangeStart: hasDuration
                ? (v) {
                    setState(() => _dragValue = v);
                    widget.onInteractStart();
                  }
                : null,
            onChanged: hasDuration ? (v) => setState(() => _dragValue = v) : null,
            onChangeEnd: hasDuration
                ? (v) {
                    final target = Duration(milliseconds: (duration.inMilliseconds * v).round());
                    controller.seek(target);
                    setState(() => _dragValue = null);
                    widget.onInteractEnd();
                  }
                : null,
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(_formatDuration(previewDuration), style: style.timeTextStyle),
              const SizedBox(width: 12),
              Expanded(child: scrubber),
              const SizedBox(width: 12),
              Text(_formatDuration(remaining, negative: true), style: style.timeTextStyle),
            ],
          );
        },
      ),
    );
  }
}

/// Wraps [PlayerScrubberSlider] and listens to an optional external buffered
/// progress [ValueListenable].
class _BufferedScrubber extends StatelessWidget {
  final double value;
  final ValueListenable<double>? bufferedProgress;
  final Color activeColor;
  final Color bufferedColor;
  final Color inactiveColor;
  final double trackHeight;
  final double activeTrackHeight;
  final double thumbRadius;
  final double activeThumbRadius;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  const _BufferedScrubber({
    required this.value,
    required this.bufferedProgress,
    required this.activeColor,
    required this.bufferedColor,
    required this.inactiveColor,
    required this.trackHeight,
    required this.activeTrackHeight,
    required this.thumbRadius,
    required this.activeThumbRadius,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final listenable = bufferedProgress;
    if (listenable == null) {
      return PlayerScrubberSlider(
        value: value,
        bufferedValue: 0,
        activeColor: activeColor,
        bufferedColor: bufferedColor,
        inactiveColor: inactiveColor,
        trackHeight: trackHeight,
        activeTrackHeight: activeTrackHeight,
        thumbRadius: thumbRadius,
        activeThumbRadius: activeThumbRadius,
        onChangeStart: onChangeStart,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: listenable,
      builder: (context, buffered, _) {
        return PlayerScrubberSlider(
          value: value,
          bufferedValue: buffered,
          activeColor: activeColor,
          bufferedColor: bufferedColor,
          inactiveColor: inactiveColor,
          trackHeight: trackHeight,
          activeTrackHeight: activeTrackHeight,
          thumbRadius: thumbRadius,
          activeThumbRadius: activeThumbRadius,
          onChangeStart: onChangeStart,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        );
      },
    );
  }
}
