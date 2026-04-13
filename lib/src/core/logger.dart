import 'package:flutter/foundation.dart';

/// 日志级别枚举。
/// Log level enumeration.
enum LogLevel { debug, info, warning, error }

/// 统一日志工具，支持按级别过滤输出。
/// Unified logger utility with level-based filtering.
class Logger {
  static LogLevel _level = LogLevel.info;
  static final String _tag = 'CacheVideoPlayer';

  /// 设置全局日志级别。
  /// Sets the global log level.
  static set level(LogLevel level) => _level = level;

  /// 输出调试级别日志。
  /// Prints a debug-level log message.
  static void debug(String message, [Object? error]) {
    if (_level.index <= LogLevel.debug.index) {
      debugPrint('[$_tag][DEBUG] $message');
      if (error != null) debugPrint('  Error: $error');
    }
  }

  /// 输出信息级别日志。
  /// Prints an info-level log message.
  static void info(String message) {
    if (_level.index <= LogLevel.info.index) {
      debugPrint('[$_tag][INFO] $message');
    }
  }

  /// 输出警告级别日志。
  /// Prints a warning-level log message.
  static void warning(String message, [Object? error]) {
    if (_level.index <= LogLevel.warning.index) {
      debugPrint('[$_tag][WARN] $message');
      if (error != null) debugPrint('  Error: $error');
    }
  }

  /// 输出错误级别日志，可附带异常和堆栈。
  /// Prints an error-level log message, optionally with error and stack trace.
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (_level.index <= LogLevel.error.index) {
      debugPrint('[$_tag][ERROR] $message');
      if (error != null) debugPrint('  Error: $error');
      if (stackTrace != null) debugPrint('  Stack: $stackTrace');
    }
  }
}
