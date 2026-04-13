import 'package:flutter/material.dart';
import '../../data/models/chunk_bitmap.dart';

/// 缓存指示器组件，用 CustomPaint 可视化每个分片的缓存状态。
/// Cache indicator widget visualizing each chunk's cache status via CustomPaint.
class CacheIndicator extends StatelessWidget {
  final ChunkBitmap? bitmap;
  final int totalChunks;
  final double height;
  final Color cachedColor;
  final Color uncachedColor;

  const CacheIndicator({
    super.key,
    required this.bitmap,
    required this.totalChunks,
    this.height = 3,
    this.cachedColor = Colors.blue,
    this.uncachedColor = Colors.transparent,
  });

  @override
  Widget build(BuildContext context) {
    if (bitmap == null || totalChunks == 0) {
      return SizedBox(height: height);
    }

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _CachePainter(
          bitmap: bitmap!,
          totalChunks: totalChunks,
          cachedColor: cachedColor,
          uncachedColor: uncachedColor,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _CachePainter extends CustomPainter {
  final ChunkBitmap bitmap;
  final int totalChunks;
  final Color cachedColor;
  final Color uncachedColor;

  _CachePainter({
    required this.bitmap,
    required this.totalChunks,
    required this.cachedColor,
    required this.uncachedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chunkWidth = size.width / totalChunks;
    final cachedPaint = Paint()..color = cachedColor;
    final uncachedPaint = Paint()..color = uncachedColor;

    for (int i = 0; i < totalChunks; i++) {
      final rect = Rect.fromLTWH(i * chunkWidth, 0, chunkWidth, size.height);
      canvas.drawRect(rect, bitmap.isChunkCompleted(i) ? cachedPaint : uncachedPaint);
    }
  }

  @override
  bool shouldRepaint(_CachePainter oldDelegate) {
    return oldDelegate.bitmap != bitmap;
  }
}
