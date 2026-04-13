import 'package:flutter/material.dart';

/// 构建 Material 3 暗色主题。
/// Builds the Material 3 dark theme.
ThemeData buildDarkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorSchemeSeed: Colors.blue,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      activeTrackColor: Colors.blue.shade300,
      inactiveTrackColor: Colors.blue.shade800,
    ),
  );
}
