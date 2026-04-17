import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 负责把 Flutter assets 中的媒体懒抽取到本地文件，供原生播放器使用。
/// Extracts Flutter assets to a local file so native players can read them.
class AssetExtractor {
  AssetExtractor._();

  /// 同一 asset 的抽取过程只进行一次，多次并发调用共享同一个 future。
  /// Concurrent extractions of the same asset share a single future.
  static final Map<String, Future<String>> _inflight = <String, Future<String>>{};

  /// 返回抽取后落地文件的绝对路径；若已存在则直接复用。
  ///
  /// Returns the absolute path of the extracted file; reuses existing files.
  static Future<String> extract(String assetPath, {AssetBundle? bundle}) {
    if (kIsWeb) {
      throw UnsupportedError(
        'AssetExtractor is not supported on web; asset URLs are served by '
        'the browser directly. Use the asset path as a network URL instead.',
      );
    }
    final key = assetPath;
    final inflight = _inflight[key];
    if (inflight != null) return inflight;
    final future = _doExtract(assetPath, bundle ?? rootBundle);
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  static Future<String> _doExtract(String assetPath, AssetBundle bundle) async {
    final tempDir = await getTemporaryDirectory();
    final root = Directory('${tempDir.path}/flutter_cache_video_player/assets');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final hash = sha1.convert(assetPath.codeUnits).toString();
    final baseName = assetPath.split('/').last;
    final safeName = baseName.isEmpty ? 'media' : baseName;
    final outPath = '${root.path}/$hash-$safeName';
    final file = File(outPath);
    if (await file.exists() && await file.length() > 0) {
      return outPath;
    }
    final bytes = await bundle.load(assetPath);
    final buffer = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    final sink = file.openWrite();
    sink.add(buffer);
    await sink.flush();
    await sink.close();
    return outPath;
  }
}
