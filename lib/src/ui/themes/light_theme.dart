import 'package:flutter/material.dart';

/// 构建 Material 3 亮色主题。
/// Builds the Material 3 light theme.
ThemeData buildLightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    colorSchemeSeed: Colors.blue,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      activeTrackColor: Colors.blue,
      inactiveTrackColor: Colors.blue.withValues(alpha: 0.2),
    ),
  );
}
