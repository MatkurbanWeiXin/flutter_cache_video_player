/// HTTP Range 头解析器。
/// HTTP Range header parser.
class RangeHeader {
  final int start;
  final int? end;

  RangeHeader({required this.start, this.end});

  /// 解析 Range 头字符串，返回 null 表示没有有效的 Range。
  /// Parses a Range header string; returns null if no valid range is found.
  static RangeHeader? parse(String? header, int totalBytes) {
    if (header == null || header.isEmpty) return null;

    final match = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(header);
    if (match == null) return null;

    final startStr = match.group(1) ?? '';
    final endStr = match.group(2) ?? '';

    if (startStr.isEmpty && endStr.isEmpty) return null;

    int start;
    int? end;

    if (startStr.isEmpty) {
      // suffix range: bytes=-500 means last 500 bytes
      final suffix = int.tryParse(endStr);
      if (suffix == null) return null;
      start = totalBytes - suffix;
      if (start < 0) start = 0;
      end = totalBytes - 1;
    } else {
      start = int.tryParse(startStr) ?? 0;
      end = endStr.isEmpty ? null : int.tryParse(endStr);
    }

    if (end != null && end >= totalBytes) {
      end = totalBytes - 1;
    }

    return RangeHeader(start: start, end: end);
  }

  /// 获取解析后的结束字节位置。
  /// Returns the resolved end byte position.
  int resolvedEnd(int totalBytes) => end ?? (totalBytes - 1);

  /// 计算 Content-Length（字节数）。
  /// Calculates the Content-Length in bytes.
  int contentLength(int totalBytes) => resolvedEnd(totalBytes) - start + 1;
}
