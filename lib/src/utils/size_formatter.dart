/// 文件大小格式化工具，将字节数转为可读字符串。
/// File size formatter converting bytes to human-readable strings.
class SizeFormatter {
  /// 将字节数格式化为 B / KB / MB / GB 字符串。
  /// Formats a byte count as a B / KB / MB / GB string.
  static String format(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
