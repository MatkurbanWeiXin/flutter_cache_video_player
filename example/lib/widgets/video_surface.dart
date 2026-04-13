import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/flutter_cache_video_player.dart';
import 'package:signals/signals_flutter.dart';

/// 视频渲染面，处理多平台差异（Web / Native）和播放状态切换。
class VideoSurface extends StatelessWidget {
  final PlayerService playerService;
  final ReadonlySignal<PlayState> playState;
  final ReadonlySignal<bool> isBuffering;
  final ReadonlySignal<String?> errorMessage;

  const VideoSurface({
    super.key,
    required this.playerService,
    required this.playState,
    required this.isBuffering,
    required this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final ps = playState.watch(context);
    final err = errorMessage.watch(context);
    final buffering = isBuffering.watch(context);

    // Error
    if (ps == PlayState.error) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                err ?? '播放失败',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                final url = playerService.state.currentUrl;
                if (url != null) playerService.open(url);
              },
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('重试', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    // Web: 始终保持 HtmlElementView 挂载，避免 DOM 卸载/重挂导致需要双击播放
    if (kIsWeb) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const AspectRatio(
              aspectRatio: 16 / 9,
              child: HtmlElementView(viewType: 'flutter-cache-video-player-web'),
            ),
            if (ps == PlayState.loading || buffering) const CircularProgressIndicator(),
          ],
        ),
      );
    }

    // Native
    final textureId = playerService.textureId;
    final isLoading = ps == PlayState.loading;

    if (isLoading || buffering) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (buffering && !isLoading && textureId != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Texture(textureId: textureId),
              ),
            const CircularProgressIndicator(),
          ],
        ),
      );
    }

    if (textureId == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Texture(textureId: textureId),
      ),
    );
  }
}
