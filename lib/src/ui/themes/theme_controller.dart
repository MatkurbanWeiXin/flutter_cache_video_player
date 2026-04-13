import 'package:flutter/material.dart';

/// 主题控制器，基于 ValueNotifier 管理当前 ThemeMode。
/// Theme controller managing the current ThemeMode via ValueNotifier.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  /// 设置主题模式。
  /// Sets the theme mode.
  void setThemeMode(ThemeMode mode) {
    value = mode;
  }

  /// 在亮色与暗色主题之间切换。
  /// Toggles between light and dark themes.
  void toggleTheme() {
    if (value == ThemeMode.dark) {
      value = ThemeMode.light;
    } else {
      value = ThemeMode.dark;
    }
  }
}
