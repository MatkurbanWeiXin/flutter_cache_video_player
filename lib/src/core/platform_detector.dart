import 'package:universal_platform/universal_platform.dart';

/// 应用平台类型枚举。
/// Enumeration of supported application platform types.
enum AppPlatformType { android, ios, windows, macos, linux, web }

/// 平台检测工具类，提供统一的平台判断能力。
/// 底层基于 [UniversalPlatform]，同时兼容原生与 Web。
///
/// Platform detection utility providing unified platform queries.
/// Backed by [UniversalPlatform] so it works on both native and web targets.
sealed class PlatformDetector {
  /// 是否运行在 Web 平台。
  /// Whether the app is running on the web platform.
  static bool get isWeb => UniversalPlatform.isWeb;

  /// 是否运行在原生平台（非 Web）。
  /// Whether the app is running on a native (non-web) platform.
  static bool get isNative => !UniversalPlatform.isWeb;

  /// 是否为 Android。
  /// Whether the current platform is Android.
  static bool get isAndroid => UniversalPlatform.isAndroid;

  /// 是否为 iOS。
  /// Whether the current platform is iOS.
  static bool get isIOS => UniversalPlatform.isIOS;

  /// 是否为 Windows。
  /// Whether the current platform is Windows.
  static bool get isWindows => UniversalPlatform.isWindows;

  /// 是否为 macOS。
  /// Whether the current platform is macOS.
  static bool get isMacOS => UniversalPlatform.isMacOS;

  /// 是否为 Linux。
  /// Whether the current platform is Linux.
  static bool get isLinux => UniversalPlatform.isLinux;

  /// 是否为移动平台（Android / iOS）。
  /// Whether the current platform is mobile (Android / iOS).
  static bool get isMobile => UniversalPlatform.isAndroid || UniversalPlatform.isIOS;

  /// 是否为桌面平台（Windows / macOS / Linux）。
  /// Whether the current platform is desktop (Windows / macOS / Linux).
  static bool get isDesktop =>
      UniversalPlatform.isWindows || UniversalPlatform.isMacOS || UniversalPlatform.isLinux;

  /// 获取当前平台类型。
  /// Returns the current platform type.
  static AppPlatformType get current {
    if (UniversalPlatform.isWeb) return AppPlatformType.web;
    if (UniversalPlatform.isAndroid) return AppPlatformType.android;
    if (UniversalPlatform.isIOS) return AppPlatformType.ios;
    if (UniversalPlatform.isWindows) return AppPlatformType.windows;
    if (UniversalPlatform.isMacOS) return AppPlatformType.macos;
    if (UniversalPlatform.isLinux) return AppPlatformType.linux;
    return AppPlatformType.linux;
  }

  /// 获取建议的 Worker 并发数（移动端 2，桌面端 4，Web 0）。
  /// Returns the recommended worker count (mobile: 2, desktop: 4, web: 0).
  static int get recommendedWorkerCount {
    if (isWeb) return 0;
    return isMobile ? 2 : 4;
  }
}
