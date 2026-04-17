import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../data/enums/play_state.dart';
import '../player/flutter_cache_video_player_controller.dart';

/// 视频渲染组件，只负责显示视频画面和基本状态（加载/缓冲/错误）。
/// 控制栏、进度条等由使用者自行实现。
///
/// Video rendering widget that only renders video frames and basic states
/// (loading/buffering/error). Controls, progress bars, etc. are the
/// caller's responsibility.
class FlutterCacheVideoPlayerView extends StatelessWidget {
  /// 播放控制器实例。
  final FlutterCacheVideoPlayerController controller;

  /// 视频宽高比。
  ///
  /// 默认 `null`，表示使用原生播放器上报的视频实际宽高比，避免竖向视频
  /// 被强制拉伸到 16:9。上报之前会临时按 16:9 占位。
  ///
  /// 若显式传入数值，则始终使用该宽高比（忽略原生上报）。
  ///
  /// Video aspect ratio.
  ///
  /// `null` (default) lets the view follow the natural aspect ratio reported
  /// by the native player, so portrait videos are not stretched to 16:9.
  /// Before the size is known the view falls back to 16:9 as a placeholder.
  ///
  /// Pass a concrete value to force a fixed aspect ratio.
  final double? aspectRatio;

  /// 背景色，默认黑色。
  final Color backgroundColor;

  /// 自定义错误视图构建器。若为 null 则使用默认错误视图。
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;

  /// 自定义加载/缓冲视图构建器。若为 null 则使用默认 CircularProgressIndicator。
  final Widget Function(BuildContext context)? loadingBuilder;

  const FlutterCacheVideoPlayerView({
    super.key,
    required this.controller,
    this.aspectRatio,
    this.backgroundColor = Colors.black,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final PlayState state = controller.playState.watch(context);
    final buffering = controller.isBuffering.watch(context);

    // Resolve the aspect ratio to use for this build:
    //  * explicit `aspectRatio` param always wins
    //  * otherwise use the native-reported natural video size
    //  * fall back to 16:9 when nothing is known yet
    final double effectiveAspectRatio;
    if (aspectRatio != null) {
      effectiveAspectRatio = aspectRatio!;
    } else {
      final reported = controller.videoAspectRatio.watch(context);
      effectiveAspectRatio = (reported != null && reported > 0) ? reported : 16 / 9;
    }

    // Error
    if (state == PlayState.error) {
      final err = controller.errorMessage.watch(context);
      return Container(
        color: backgroundColor,
        alignment: Alignment.center,
        child: errorBuilder != null ? errorBuilder!(context, err) : const SizedBox(),
      );
    }

    // Web: keep HtmlElementView mounted to avoid DOM unmount/remount issues
    if (kIsWeb) {
      return ColoredBox(
        color: backgroundColor,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: effectiveAspectRatio,
              child: const HtmlElementView(viewType: 'flutter-cache-video-player-web'),
            ),
            if (state == PlayState.loading || buffering)
              loadingBuilder?.call(context) ?? CircularProgressIndicator(),
          ],
        ),
      );
    }

    // Native — loading / buffering
    final textureId = controller.textureId;
    if (state == PlayState.loading || buffering) {
      return Container(
        color: backgroundColor,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (buffering && state != PlayState.loading && textureId != null)
              AspectRatio(
                aspectRatio: effectiveAspectRatio,
                child: Texture(textureId: textureId),
              ),
            loadingBuilder?.call(context) ?? CircularProgressIndicator(),
          ],
        ),
      );
    }

    // Native — no texture yet
    if (textureId == null) {
      return Container(
        color: backgroundColor,
        alignment: Alignment.center,
        child: loadingBuilder?.call(context) ?? CircularProgressIndicator(),
      );
    }

    // Native — normal playback
    return Container(
      color: backgroundColor,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: effectiveAspectRatio,
        child: Texture(textureId: textureId),
      ),
    );
  }
}
