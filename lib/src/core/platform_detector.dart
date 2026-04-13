import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'dart:io';

/// 应用平台类型枚举。
/// Enumeration of supported application platform types.
enum AppPlatformType { android, ios, windows, macos, linux, web }

/// 平台检测工具类，提供统一的平台判断能力。
/// Platform detection utility providing unified platform queries.
class PlatformDetector {
  /// 是否运行在 Web 平台。
  /// Whether the app is running on the web platform.
  static bool get isWeb => kIsWeb;

  /// 是否运行在原生平台（非 Web）。
  /// Whether the app is running on a native (non-web) platform.
  static bool get isNative => !kIsWeb;

  /// 是否为移动平台（Android / iOS）。
  /// Whether the current platform is mobile (Android / iOS).
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 是否为桌面平台（Windows / macOS / Linux）。
  /// Whether the current platform is desktop (Windows / macOS / Linux).
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 获取当前平台类型。
  /// Returns the current platform type.
  static AppPlatformType get current {
    if (kIsWeb) return AppPlatformType.web;
    if (Platform.isAndroid) return AppPlatformType.android;
    if (Platform.isIOS) return AppPlatformType.ios;
    if (Platform.isWindows) return AppPlatformType.windows;
    if (Platform.isMacOS) return AppPlatformType.macos;
    if (Platform.isLinux) return AppPlatformType.linux;
    return AppPlatformType.linux;
  }

  /// 获取建议的 Worker 并发数（移动端 2，桌面端 4，Web 0）。
  /// Returns the recommended worker count (mobile: 2, desktop: 4, web: 0).
  static int get recommendedWorkerCount {
    if (kIsWeb) return 0;
    return isMobile ? 2 : 4;
  }
}
