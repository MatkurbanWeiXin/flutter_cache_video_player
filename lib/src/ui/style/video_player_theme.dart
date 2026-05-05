import 'dart:ui';
import 'package:flutter/material.dart';

/// The theme configuration for the video player.
@immutable
class VideoPlayerTheme extends ThemeExtension<VideoPlayerTheme> {
  /// Foreground color for overlay glyphs and text.
  final Color foregroundColor;

  /// Background color behind the video frame.
  final Color backgroundColor;

  /// Horizontal spacing between the three center buttons.
  final double centerControlsSpacing;

  /// The size of the central play/pause button icon.
  final double centerPlayButtonIconSize;

  /// The size of the skip forward/backward button icons.
  final double centerSkipButtonIconSize;

  /// The background color for the center buttons.
  final Color centerButtonBackgroundColor;

  /// Inset of the top bar.
  final EdgeInsets topBarPadding;

  /// Inset of the bottom scrubber row.
  final EdgeInsets bottomBarPadding;

  /// Text style of the time labels flanking the scrubber.
  final TextStyle timeTextStyle;

  /// Active (played) segment color.
  final Color scrubberActiveColor;

  /// Buffered (cached) segment color.
  final Color scrubberBufferedColor;

  /// Inactive (unplayed) segment color.
  final Color scrubberInactiveColor;

  /// Scrubber track thickness at rest.
  final double scrubberTrackHeight;

  /// Scrubber track thickness while scrubbing.
  final double scrubberActiveTrackHeight;

  /// Scrubber thumb radius at rest.
  final double scrubberThumbRadius;

  /// Scrubber thumb radius while the user is pressing or dragging.
  final double scrubberActiveThumbRadius;

  const VideoPlayerTheme({
    this.foregroundColor = Colors.white,
    this.backgroundColor = Colors.black,
    this.centerControlsSpacing = 56,
    this.centerPlayButtonIconSize = 48,
    this.centerSkipButtonIconSize = 32,
    this.centerButtonBackgroundColor = const Color(0x4D000000), // Colors.black38
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

  @override
  VideoPlayerTheme copyWith({
    Color? foregroundColor,
    Color? backgroundColor,
    double? centerControlsSpacing,
    double? centerPlayButtonIconSize,
    double? centerSkipButtonIconSize,
    Color? centerButtonBackgroundColor,
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
    return VideoPlayerTheme(
      foregroundColor: foregroundColor ?? this.foregroundColor,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      centerControlsSpacing: centerControlsSpacing ?? this.centerControlsSpacing,
      centerPlayButtonIconSize: centerPlayButtonIconSize ?? this.centerPlayButtonIconSize,
      centerSkipButtonIconSize: centerSkipButtonIconSize ?? this.centerSkipButtonIconSize,
      centerButtonBackgroundColor: centerButtonBackgroundColor ?? this.centerButtonBackgroundColor,
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

  @override
  VideoPlayerTheme lerp(ThemeExtension<VideoPlayerTheme>? other, double t) {
    if (other is! VideoPlayerTheme) {
      return this;
    }
    return VideoPlayerTheme(
      foregroundColor: Color.lerp(foregroundColor, other.foregroundColor, t) ?? foregroundColor,
      backgroundColor: Color.lerp(backgroundColor, other.backgroundColor, t) ?? backgroundColor,
      centerControlsSpacing:
          lerpDouble(centerControlsSpacing, other.centerControlsSpacing, t) ??
          centerControlsSpacing,
      centerPlayButtonIconSize:
          lerpDouble(centerPlayButtonIconSize, other.centerPlayButtonIconSize, t) ??
          centerPlayButtonIconSize,
      centerSkipButtonIconSize:
          lerpDouble(centerSkipButtonIconSize, other.centerSkipButtonIconSize, t) ??
          centerSkipButtonIconSize,
      centerButtonBackgroundColor:
          Color.lerp(centerButtonBackgroundColor, other.centerButtonBackgroundColor, t) ??
          centerButtonBackgroundColor,
      topBarPadding: EdgeInsets.lerp(topBarPadding, other.topBarPadding, t) ?? topBarPadding,
      bottomBarPadding:
          EdgeInsets.lerp(bottomBarPadding, other.bottomBarPadding, t) ?? bottomBarPadding,
      timeTextStyle: TextStyle.lerp(timeTextStyle, other.timeTextStyle, t) ?? timeTextStyle,
      scrubberActiveColor:
          Color.lerp(scrubberActiveColor, other.scrubberActiveColor, t) ?? scrubberActiveColor,
      scrubberBufferedColor:
          Color.lerp(scrubberBufferedColor, other.scrubberBufferedColor, t) ??
          scrubberBufferedColor,
      scrubberInactiveColor:
          Color.lerp(scrubberInactiveColor, other.scrubberInactiveColor, t) ??
          scrubberInactiveColor,
      scrubberTrackHeight:
          lerpDouble(scrubberTrackHeight, other.scrubberTrackHeight, t) ?? scrubberTrackHeight,
      scrubberActiveTrackHeight:
          lerpDouble(scrubberActiveTrackHeight, other.scrubberActiveTrackHeight, t) ??
          scrubberActiveTrackHeight,
      scrubberThumbRadius:
          lerpDouble(scrubberThumbRadius, other.scrubberThumbRadius, t) ?? scrubberThumbRadius,
      scrubberActiveThumbRadius:
          lerpDouble(scrubberActiveThumbRadius, other.scrubberActiveThumbRadius, t) ??
          scrubberActiveThumbRadius,
    );
  }
}
