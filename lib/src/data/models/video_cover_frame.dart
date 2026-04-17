import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

/// 视频封面候选帧。
///
/// Represents one candidate cover frame extracted from a video.
@immutable
class VideoCoverFrame {
  /// 封面图片（PNG）。Native 平台上 [XFile.path] 指向真实文件；Web 上为 blob URL。
  /// Cover PNG image. On native platforms [XFile.path] is a real file path;
  /// on the web it is a blob URL.
  final XFile image;

  /// 帧在视频中的时间戳。
  /// Position of the frame within the video.
  final Duration position;

  /// 平均亮度评分（0.0 – 1.0，越大越亮）。用于过滤纯黑帧、方便排序。
  /// Average brightness score (0.0–1.0, higher is brighter). Used to filter
  /// pure-black frames and rank candidates.
  final double brightness;

  const VideoCoverFrame({required this.image, required this.position, required this.brightness});

  @override
  String toString() =>
      'VideoCoverFrame(position: $position, brightness: ${brightness.toStringAsFixed(3)}, '
      'path: ${image.path})';
}
