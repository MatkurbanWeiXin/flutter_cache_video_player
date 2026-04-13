import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 文件系统工具类，管理缓存目录与文件操作。
/// File system utility managing cache directories and file operations.
class FileUtils {
  static String? _cacheDir;

  /// 获取缓存根目录路径（移动端用 Cache，桌面端用 AppSupport）。
  /// Returns the cache root directory path (Cache on mobile, AppSupport on desktop).
  static Future<String> getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;
    if (kIsWeb) {
      _cacheDir = '';
      return _cacheDir!;
    }
    final Directory dir;
    if (Platform.isAndroid || Platform.isIOS) {
      dir = await getApplicationCacheDirectory();
    } else {
      dir = await getApplicationSupportDirectory();
    }
    final mediaDir = Directory('${dir.path}/media');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    _cacheDir = mediaDir.path;
    return _cacheDir!;
  }

  /// 获取指定 URL 哈希对应的媒体目录，不存在时自动创建。
  /// Returns the media directory for a given URL hash, creating it if absent.
  static Future<String> getMediaDir(String urlHash) async {
    final base = await getCacheDirectory();
    final dir = Directory('$base/$urlHash');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// 返回指定索引的分片文件名。
  /// Returns the chunk file name for the given index.
  static String chunkFileName(int index) => 'chunk_$index.bin';

  /// 返回合并后的完整文件名。
  /// Returns the merged output file name.
  static String mergedFileName() => 'data.bin';

  /// 递归计算指定目录的总大小（字节）。
  /// Recursively calculates the total size in bytes of a directory.
  static Future<int> getDirectorySize(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return 0;
    int size = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        size += await entity.length();
      }
    }
    return size;
  }

  /// 递归删除指定目录及其所有内容。
  /// Recursively deletes a directory and all of its contents.
  static Future<void> deleteDirectory(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
