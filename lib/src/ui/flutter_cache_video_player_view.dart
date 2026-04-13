import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';
import '../player/flutter_cache_video_player_controller.dart';
import '../player/flutter_cache_video_player_state.dart';

/// 视频渲染组件，只负责显示视频画面和基本状态（加载/缓冲/错误）。
/// 控制栏、进度条等由使用者自行实现。
///
/// Video rendering widget that only renders video frames and basic states
/// (loading/buffering/error). Controls, progress bars, etc. are the
/// caller's responsibility.
class FlutterCacheVideoPlayerView extends StatelessWidget {
  /// 播放控制器实例。
  final FlutterCacheVideoPlayerController controller;

  /// 视频宽高比，默认 16:9。
  final double aspectRatio;

  /// 背景色，默认黑色。
  final Color backgroundColor;

  /// 自定义错误视图构建器。若为 null 则使用默认错误视图。
  final Widget Function(BuildContext context, String? errorMessage)? errorBuilder;

  /// 自定义加载/缓冲视图构建器。若为 null 则使用默认 CircularProgressIndicator。
  final Widget Function(BuildContext context)? loadingBuilder;

  const FlutterCacheVideoPlayerView({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
    this.backgroundColor = Colors.black,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final ps = controller.state.playState.watch(context);
    final buffering = controller.state.isBuffering.watch(context);

    // Error
    if (ps == PlayState.error) {
      final err = controller.state.errorMessage.watch(context);
      return Container(
        color: backgroundColor,
        alignment: Alignment.center,
        child: errorBuilder != null ? errorBuilder!(context, err) : const SizedBox(),
      );
    }

    // Web: keep HtmlElementView mounted to avoid DOM unmount/remount issues
    if (kIsWeb) {
      return Container(
        color: backgroundColor,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: const HtmlElementView(viewType: 'flutter-cache-video-player-web'),
            ),
            if (ps == PlayState.loading || buffering) _buildLoading(context),
          ],
        ),
      );
    }

    // Native — loading / buffering
    final textureId = controller.textureId;
    if (ps == PlayState.loading || buffering) {
      return Container(
        color: backgroundColor,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (buffering && ps != PlayState.loading && textureId != null)
              AspectRatio(
                aspectRatio: aspectRatio,
                child: Texture(textureId: textureId),
              ),
            _buildLoading(context),
          ],
        ),
      );
    }

    // Native — no texture yet
    if (textureId == null) {
      return Container(
        color: backgroundColor,
        alignment: Alignment.center,
        child: _buildLoading(context),
      );
    }

    // Native — normal playback
    return Container(
      color: backgroundColor,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Texture(textureId: textureId),
      ),
    );
  }

  Widget _buildLoading(BuildContext context) {
    return loadingBuilder != null ? loadingBuilder!(context) : const CircularProgressIndicator();
  }
}
