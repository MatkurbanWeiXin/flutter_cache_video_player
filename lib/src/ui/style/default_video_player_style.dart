import 'package:flutter/material.dart';

/// [DefaultVideoPlayer] 的视觉样式，所有可自定义的颜色、尺寸、字体都集中在这里。
/// Visual configuration for [DefaultVideoPlayer] – colors, sizes and text styles.
@immutable
class DefaultVideoPlayerStyle {
  /// 覆盖层前景色（图标、文字默认颜色）。
  /// Foreground color for overlay glyphs and text.
  final Color foregroundColor;

  /// 播放器画面背景色。
  /// Background color behind the video frame.
  final Color backgroundColor;

  /// 顶/底部渐变遮罩的深度（0 = 不绘制）。
  /// Intensity of the top/bottom gradient scrim (0 disables it).
  final double scrimIntensity;

  /// 是否启用极浅的整屏毛玻璃遮罩。
  /// When true a faint full-screen blur is layered under the controls.
  final bool enableGlassmorphism;

  /// 毛玻璃模糊强度。
  /// Backdrop blur sigma when [enableGlassmorphism] is true.
  final double glassmorphismBlur;

  /// 中央主按钮（播放/暂停）图标尺寸。
  /// Icon size of the center play/pause button.
  final double centerPrimaryIconSize;

  /// 中央副按钮（快退/快进 10 秒）图标尺寸。
  /// Icon size of the center skip-back / skip-forward buttons.
  final double centerSecondaryIconSize;

  /// 顶部栏图标尺寸。
  /// Icon size used by the top bar.
  final double topBarIconSize;

  /// 中央三个按钮之间的水平间距。
  /// Horizontal spacing between the three center buttons.
  final double centerControlsSpacing;

  /// 顶部栏内边距。
  /// Inset of the top bar.
  final EdgeInsets topBarPadding;

  /// 底部进度条行的内边距。
  /// Inset of the bottom scrubber row.
  final EdgeInsets bottomBarPadding;

  /// 进度条两侧时间文字的样式（等宽数字、细字号）。
  /// Text style of the time labels flanking the scrubber.
  final TextStyle timeTextStyle;

  /// 进度条已播放部分颜色。
  /// Active (played) segment color.
  final Color scrubberActiveColor;

  /// 进度条已缓存部分颜色。
  /// Buffered (cached) segment color.
  final Color scrubberBufferedColor;

  /// 进度条未播放部分颜色。
  /// Inactive (unplayed) segment color.
  final Color scrubberInactiveColor;

  /// 进度条静止厚度。
  /// Scrubber track thickness at rest.
  final double scrubberTrackHeight;

  /// 进度条拖动时厚度。
  /// Scrubber track thickness while scrubbing.
  final double scrubberActiveTrackHeight;

  /// 进度条滑块半径（静止）。
  /// Scrubber thumb radius at rest.
  final double scrubberThumbRadius;

  /// 按住/拖动时放大的滑块半径。
  /// Scrubber thumb radius while the user is pressing or dragging.
  final double scrubberActiveThumbRadius;

  const DefaultVideoPlayerStyle({
    this.foregroundColor = Colors.white,
    this.backgroundColor = Colors.black,
    this.scrimIntensity = 0.55,
    this.enableGlassmorphism = false,
    this.glassmorphismBlur = 8.0,
    this.centerPrimaryIconSize = 56,
    this.centerSecondaryIconSize = 36,
    this.topBarIconSize = 22,
    this.centerControlsSpacing = 56,
    this.topBarPadding = const EdgeInsets.fromLTRB(12, 12, 12, 12),
    this.bottomBarPadding = const EdgeInsets.fromLTRB(16, 6, 16, 14),
    this.timeTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      fontWeight: FontWeight.w500,
      height: 1.0,
    ),
    this.scrubberActiveColor = Colors.white,
    this.scrubberBufferedColor = const Color(0xB3FFFFFF),
    this.scrubberInactiveColor = const Color(0x40FFFFFF),
    this.scrubberTrackHeight = 2.0,
    this.scrubberActiveTrackHeight = 6.0,
    this.scrubberThumbRadius = 5.0,
    this.scrubberActiveThumbRadius = 9.0,
  });

  DefaultVideoPlayerStyle copyWith({
    Color? foregroundColor,
    Color? backgroundColor,
    double? scrimIntensity,
    bool? enableGlassmorphism,
    double? glassmorphismBlur,
    double? centerPrimaryIconSize,
    double? centerSecondaryIconSize,
    double? topBarIconSize,
    double? centerControlsSpacing,
    EdgeInsets? topBarPadding,
    EdgeInsets? bottomBarPadding,
    TextStyle? timeTextStyle,
    Color? scrubberActiveColor,
    Color? scrubberBufferedColor,
    Color? scrubberInactiveColor,
    double? scrubberTrackHeight,
    double? scrubberActiveTrackHeight,
    double? scrubberThumbRadius,
    double? scrubberActiveThumbRadius,
  }) {
    return DefaultVideoPlayerStyle(
      foregroundColor: foregroundColor ?? this.foregroundColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      scrimIntensity: scrimIntensity ?? this.scrimIntensity,
      enableGlassmorphism: enableGlassmorphism ?? this.enableGlassmorphism,
      glassmorphismBlur: glassmorphismBlur ?? this.glassmorphismBlur,
      centerPrimaryIconSize: centerPrimaryIconSize ?? this.centerPrimaryIconSize,
      centerSecondaryIconSize: centerSecondaryIconSize ?? this.centerSecondaryIconSize,
      topBarIconSize: topBarIconSize ?? this.topBarIconSize,
      centerControlsSpacing: centerControlsSpacing ?? this.centerControlsSpacing,
      topBarPadding: topBarPadding ?? this.topBarPadding,
      bottomBarPadding: bottomBarPadding ?? this.bottomBarPadding,
      timeTextStyle: timeTextStyle ?? this.timeTextStyle,
      scrubberActiveColor: scrubberActiveColor ?? this.scrubberActiveColor,
      scrubberBufferedColor: scrubberBufferedColor ?? this.scrubberBufferedColor,
      scrubberInactiveColor: scrubberInactiveColor ?? this.scrubberInactiveColor,
      scrubberTrackHeight: scrubberTrackHeight ?? this.scrubberTrackHeight,
      scrubberActiveTrackHeight: scrubberActiveTrackHeight ?? this.scrubberActiveTrackHeight,
      scrubberThumbRadius: scrubberThumbRadius ?? this.scrubberThumbRadius,
      scrubberActiveThumbRadius: scrubberActiveThumbRadius ?? this.scrubberActiveThumbRadius,
    );
  }
}
