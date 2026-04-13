import 'dart:convert';
import 'package:crypto/crypto.dart';

/// URL 哈希工具，将 URL 转换为固定长度的 SHA256 摘要。
/// URL hashing utility that converts a URL to a fixed-length SHA256 digest.
class UrlHasher {
  /// 将 URL 转换为 16 字符的 SHA256 截断哈希。
  /// Converts a URL to a 16-character truncated SHA256 hash.
  static String hash(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
}
