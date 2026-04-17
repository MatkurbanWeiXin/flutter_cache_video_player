import 'package:flutter/material.dart';

/// 覆盖在视频画面顶部/底部的黑色渐变遮罩，用于确保纯白图标和文字的可读性。
///
/// A thin gradient scrim rendered at the top and/or bottom of the video frame
/// so that white overlay controls remain readable on bright content.
class PlayerGradientMask extends StatelessWidget {
  /// 是否启用顶部渐变。
  /// Whether to render the top scrim.
  final bool enableTop;

  /// 是否启用底部渐变。
  /// Whether to render the bottom scrim.
  final bool enableBottom;

  /// 顶部渐变高度（逻辑像素）。
  /// Height of the top scrim in logical pixels.
  final double topHeight;

  /// 底部渐变高度（逻辑像素）。
  /// Height of the bottom scrim in logical pixels.
  final double bottomHeight;

  /// 渐变深度（起始端的黑色透明度）。
  /// Scrim intensity – opacity of the dark end-stop (0.0 – 1.0).
  final double intensity;

  const PlayerGradientMask({
    super.key,
    this.enableTop = true,
    this.enableBottom = true,
    this.topHeight = 120,
    this.bottomHeight = 160,
    this.intensity = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    final topEnd = Colors.black.withValues(alpha: intensity);
    final bottomEnd = Colors.black.withValues(alpha: intensity);

    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          if (enableTop)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: topHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[topEnd, Colors.transparent],
                  ),
                ),
              ),
            ),
          if (enableBottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: <Color>[bottomEnd, Colors.transparent],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
