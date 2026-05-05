import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/src/data/enums/skip_second_type.dart';
import 'package:flutter_cache_video_player/src/ui/core_player.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../data/enums/play_state.dart';
import '../player/video_player_controller.dart';
import 'style/video_player_theme.dart';
import 'widgets/player_scrubber_slider.dart';

/// 传递给自定义槽位 builder 的上下文，提供控制器和当前样式。
/// Context passed to slot builders so callers can reuse controller and style.
class VideoPlayerSlotContext {
  final VideoPlayerController controller;
  final VideoPlayerTheme theme;
  final VoidCallback showControls;
  final VoidCallback hideControls;

  const VideoPlayerSlotContext({
    required this.controller,
    required this.theme,
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
/// thin bottom scrubber with cached progress. Tapping the frame fades the
/// controls in/out and they auto-hide during playback.
class VideoPlayer extends StatefulWidget {
  /// 底层播放控制器。
  /// The underlying player controller.
  final VideoPlayerController controller;

  /// 视频宽高比。当 [fill] 为 true 时此属性被忽略，播放器会铺满外部约束。
  /// 为 null（默认）时，使用原生播放器上报的真实宽高比，避免竖向视频被拉伸。
  /// Aspect ratio used when [fill] is false. `null` (default) follows the
  /// native video's natural aspect ratio.
  final double? aspectRatio;

  /// 是否铺满父约束（常用于全屏容器或 SizedBox.expand）。
  /// When true the player fills the available space instead of using aspect ratio.
  final bool fill;

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
  /// 不提供时，进度条会自动使用 [VideoPlayerController.cachedProgress]
  /// （由插件的缓存位图驱动）。
  ///
  /// Optional override for the cached-progress signal. When omitted the
  /// scrubber automatically reflects
  /// [VideoPlayerController.cachedProgress], which the plugin
  /// drives from the download bitmap in its cache repository.
  final ValueListenable<double>? cachedProgress;

  /// 视觉样式。
  /// Visual style bundle via theme. (Kept for overriding default theme behavior if needed, or we can just remove it and rely entirely on ThemeExtends).
  /// Let's remove it and use Theme.of(context).extension<VideoPlayerTheme>() or a local parameter, but wait, the instructions said: "完全抛弃VideoPlayerStyle，帮我写一个使用 themeExtends 控制主题的". (Completely discard VideoPlayerStyle, write one controlled by themeExtends).
  /// So let's remove `style: ` instead of adding `style:`. Wait, I shouldn't just remove `style` parameter entirely, or should I? The user said completely discard it and use themeExtends. So no `style` parameter on `VideoPlayer`. Instead it will look up `Theme.of(context).extension<VideoPlayerTheme>() ?? const VideoPlayerTheme()`.

  /// 点击左上角"完成/收起"按钮。为 null 时尝试 `Navigator.maybePop`。
  /// Handler for the leading "done" button. Falls back to `Navigator.maybePop`.
  final VoidCallback? onClose;

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
  final Widget Function(BuildContext, VideoPlayerSlotContext)? topBarBuilder;

  /// 完全自定义中央控制区。
  /// Override for the center transport controls.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? centerControlsBuilder;

  /// 完全自定义底部进度条行。
  /// Override for the bottom scrubber row.
  final Widget Function(BuildContext, VideoPlayerSlotContext)? bottomScrubberBuilder;

  /// 在默认覆盖层之后再叠加的自定义图层（例如弹幕、字幕）。
  /// Extra overlay rendered above the default controls (e.g. subtitles).
  final Widget Function(BuildContext, VideoPlayerSlotContext)? extraOverlayBuilder;

  /// 快退/快进的秒数类型
  /// Type of skip duration for the rewind / fast-forward buttons
  final SkipSecondType skipSecondType;

  const VideoPlayer({
    super.key,
    required this.controller,
    this.aspectRatio,
    this.fill = false,
    this.autoHideDelay = const Duration(seconds: 3),
    this.fadeDuration = const Duration(milliseconds: 250),
    this.initiallyVisible = true,
    this.cachedProgress,
    this.onClose,
    this.topBarActions = const <Widget>[],
    this.errorBuilder,
    this.loadingBuilder,
    this.topBarBuilder,
    this.centerControlsBuilder,
    this.bottomScrubberBuilder,
    this.extraOverlayBuilder,
    this.skipSecondType = .second10,
  });

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  late final FlutterSignal<bool> _visible = signal(widget.initiallyVisible);

  Timer? _hideTimer;

  VoidCallback? _playingDisposer;

  VoidCallback? _completedDisposer;

  @override
  void initState() {
    super.initState();
    _playingDisposer = effect(() {
      final playing = widget.controller.isPlaying.value;
      if (playing && _visible.value) {
        _scheduleAutoHide();
      } else if (!playing) {
        _hideTimer?.cancel();
      }
    });
    // Always surface controls when playback finishes so the replay button
    // is visible. Without this, if the user had hidden controls mid-playback
    // they'd see an empty frame at the end with no obvious way to restart.
    _completedDisposer = effect(() {
      final state = widget.controller.playState.value;
      if (state == PlayState.stopped) {
        _showControls(scheduleAutoHide: false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingDisposer?.call();
    _completedDisposer?.call();
    super.dispose();
  }

  void _showControls({bool scheduleAutoHide = true}) {
    _hideTimer?.cancel();
    if (!_visible.value) {
      _visible.value = true;
    }
    if (scheduleAutoHide) {
      _scheduleAutoHide();
    }
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (_visible.value) {
      _visible.value = false;
    }
  }

  void _toggleControls() {
    if (_visible.value) {
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

  VideoPlayerSlotContext _slotContext() {
    return VideoPlayerSlotContext(
      controller: widget.controller,
      theme: Theme.of(context).extension<VideoPlayerTheme>() ?? const VideoPlayerTheme(),
      showControls: _showControls,
      hideControls: _hideControls,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slot = _slotContext();
    final style = slot.theme;

    final videoView = CorePlayer(
      controller: widget.controller,
      aspectRatio: widget.aspectRatio,
      backgroundColor: style.backgroundColor,
      errorBuilder: widget.errorBuilder,
      loadingBuilder: widget.loadingBuilder,
    );

    // React to play-state changes to (re)arm the auto-hide timer.
    // See the effect registered in initState.

    final overlay = SafeArea(
      child: AnimatedSwitcher(
        duration: widget.fadeDuration,
        child: Watch((context) {
          if (!_visible.value) {
            return const SizedBox.shrink();
          }
          return Column(
            mainAxisSize: .max,
            children: <Widget>[
              widget.topBarBuilder?.call(context, slot) ??
                  Row(
                    children: [
                      IconButton(
                        onPressed: _handleClose,
                        color: style.foregroundColor,
                        icon: Icon(Icons.close),
                      ),
                      ...widget.topBarActions,
                    ],
                  ),
              Expanded(
                child: Center(
                  child:
                      widget.centerControlsBuilder?.call(context, slot) ??
                      _DefaultCenterControls(
                        slot: slot,
                        skipSecondType: widget.skipSecondType,
                        onInteract: _showControls,
                      ),
                ),
              ),
              widget.bottomScrubberBuilder?.call(context, slot) ??
                  _DefaultBottomScrubber(
                    slot: slot,
                    cachedProgress: widget.cachedProgress ?? widget.controller.cachedProgress,
                    onInteractStart: () => _hideTimer?.cancel(),
                    onInteractEnd: _scheduleAutoHide,
                  ),
            ],
          );
        }),
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
    // Resolve the effective aspect ratio: explicit value > native reported
    // video ratio > 16:9 placeholder. `watch` keeps this reactive so the
    // layout updates once the native player publishes the real size.
    //
    // When the caller didn't pass an explicit ratio we additionally clamp
    // the outer box to be at least 16:9 wide. Otherwise a portrait video
    // (e.g. 9:16 ≈ 0.56) makes AspectRatio request `width × width*16/9`,
    // which on tall layouts (Column with no fixed height) overflows the
    // parent and pushes following widgets off-screen. Clamping to ≥ 16:9
    // keeps the inline player behaving like YouTube/Bilibili: a landscape
    // "stage" with portrait videos letterboxed inside it. The inner
    // `CorePlayer` keeps using the real video ratio so the frame is never
    // stretched. Use `fill: true` (e.g. fullscreen) when you want the
    // portrait video to occupy the whole viewport.
    final double effectiveAspectRatio;
    if (widget.aspectRatio != null) {
      effectiveAspectRatio = widget.aspectRatio!;
    } else {
      final reported = widget.controller.videoAspectRatio.watch(context);
      const double minInlineAspect = 16 / 9;
      if (reported != null && reported > 0) {
        effectiveAspectRatio = reported >= minInlineAspect ? reported : minInlineAspect;
      } else {
        effectiveAspectRatio = minInlineAspect;
      }
    }
    return AspectRatio(aspectRatio: effectiveAspectRatio, child: stack);
  }
}

// ---------------------------------------------------------------------------
// Center controls
// ---------------------------------------------------------------------------

class _DefaultCenterControls extends StatelessWidget {
  final VideoPlayerSlotContext slot;
  final SkipSecondType skipSecondType;
  final VoidCallback onInteract;

  const _DefaultCenterControls({
    required this.slot,
    required this.skipSecondType,
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

  IconData _skipBackwardIcon(SkipSecondType seconds) {
    switch (seconds) {
      case .second10:
        return CupertinoIcons.gobackward_10;
      case .second15:
        return CupertinoIcons.gobackward_15;
      case .second30:
        return CupertinoIcons.gobackward_30;
      case .second45:
        return CupertinoIcons.gobackward_45;
      case .second60:
        return CupertinoIcons.gobackward_60;
    }
  }

  IconData _skipForwardIcon(SkipSecondType seconds) {
    switch (seconds) {
      case .second10:
        return CupertinoIcons.goforward_10;
      case .second15:
        return CupertinoIcons.goforward_15;
      case .second30:
        return CupertinoIcons.goforward_30;
      case .second45:
        return CupertinoIcons.goforward_45;
      case .second60:
        return CupertinoIcons.goforward_60;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = slot.theme;
    final controller = slot.controller;

    return Watch.builder(
      builder: (context) {
        final state = controller.playState.value;
        final buffering = controller.isBuffering.value;
        final isPlaying = state == PlayState.playing;
        final isCompleted = state == PlayState.stopped;
        final canInteract = state != PlayState.loading && state != PlayState.error;

        Widget centerButton;
        if (state == PlayState.loading || (buffering && !isPlaying)) {
          centerButton = SizedBox(child: CupertinoActivityIndicator(color: style.foregroundColor));
        } else if (isCompleted) {
          centerButton = IconButton(
            icon: Icon(CupertinoIcons.arrow_counterclockwise),
            color: style.foregroundColor,
            onPressed: () async {
              await controller.seek(Duration.zero);
              await controller.play();
              onInteract();
            },
          );
        } else {
          centerButton = IconButton(
            icon: Icon(isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill),
            color: style.foregroundColor,
            onPressed: canInteract
                ? () {
                    controller.playOrPause();
                    onInteract();
                  }
                : null,
          );
        }

        return Row(
          spacing: style.centerControlsSpacing,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            IconButton(
              icon: Icon(_skipBackwardIcon(skipSecondType)),
              color: style.foregroundColor,
              onPressed: canInteract ? () => _skipBy(-skipSecondType.duration) : null,
            ),
            centerButton,
            IconButton(
              icon: Icon(_skipForwardIcon(skipSecondType)),
              color: style.foregroundColor,
              onPressed: canInteract ? () => _skipBy(skipSecondType.duration) : null,
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
  final VideoPlayerSlotContext slot;
  final ValueListenable<double>? cachedProgress;
  final VoidCallback onInteractStart;
  final VoidCallback onInteractEnd;

  const _DefaultBottomScrubber({
    required this.slot,
    required this.cachedProgress,
    required this.onInteractStart,
    required this.onInteractEnd,
  });

  @override
  State<_DefaultBottomScrubber> createState() => _DefaultBottomScrubberState();
}

class _DefaultBottomScrubberState extends State<_DefaultBottomScrubber> {
  final FlutterSignal<double?> _dragValue = signal(null);

  String _formatDuration(Duration duration, {bool negative = false}) {
    if (duration.isNegative) duration = Duration.zero;
    final totalSeconds = duration.inSeconds;
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
    final style = widget.slot.theme;
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
          final effectiveValue = _dragValue.value ?? progress;
          final previewDuration = Duration(
            milliseconds: (duration.inMilliseconds * effectiveValue).round(),
          );
          final remaining = hasDuration ? (duration - previewDuration) : Duration.zero;

          return Row(
            spacing: 12,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(_formatDuration(previewDuration), style: style.timeTextStyle),
              Expanded(
                child: ValueListenableBuilder<double>(
                  valueListenable: widget.cachedProgress ?? ValueNotifier<double>(0),
                  builder: (context, cached, _) {
                    return PlayerScrubberSlider(
                      value: effectiveValue,
                      bufferedValue: cached,
                      activeColor: style.scrubberActiveColor,
                      bufferedColor: style.scrubberBufferedColor,
                      inactiveColor: style.scrubberInactiveColor,
                      trackHeight: style.scrubberTrackHeight,
                      activeTrackHeight: style.scrubberActiveTrackHeight,
                      thumbRadius: style.scrubberThumbRadius,
                      activeThumbRadius: style.scrubberActiveThumbRadius,
                      onChangeStart: hasDuration
                          ? (v) {
                              _dragValue.value = v;
                              widget.onInteractStart();
                            }
                          : null,
                      onChanged: hasDuration
                          ? (v) {
                              _dragValue.value = v;
                            }
                          : null,
                      onChangeEnd: hasDuration
                          ? (v) {
                              final target = Duration(
                                milliseconds: (duration.inMilliseconds * v).round(),
                              );
                              controller.seek(target);
                              _dragValue.value = null;
                              widget.onInteractEnd();
                            }
                          : null,
                    );
                  },
                ),
              ),
              Text(_formatDuration(remaining, negative: true), style: style.timeTextStyle),
            ],
          );
        },
      ),
    );
  }
}
