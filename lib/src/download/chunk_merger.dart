import 'dart:io';
import '../core/logger.dart';
import '../utils/file_utils.dart';

/// 分片合并器，将多个 chunk 文件合并为单一 data.bin。
/// Chunk merger that consolidates multiple chunk files into a single data.bin.
class ChunkMerger {
  /// 将指定目录下的所有分片文件合并，返回合并后路径。
  /// Merges all chunk files in the directory and returns the merged file path.
  static Future<String> mergeChunks({required String mediaDir, required int totalChunks}) async {
    final outputPath = '$mediaDir/${FileUtils.mergedFileName()}';
    final outputFile = File(outputPath);

    if (await outputFile.exists()) {
      Logger.debug('Merged file already exists: $outputPath');
      return outputPath;
    }

    final tmpPath = '$outputPath.tmp';
    final raf = await File(tmpPath).open(mode: FileMode.write);

    try {
      for (int i = 0; i < totalChunks; i++) {
        final chunkPath = '$mediaDir/${FileUtils.chunkFileName(i)}';
        final chunkFile = File(chunkPath);
        if (!await chunkFile.exists()) {
          throw StateError('Missing chunk $i at $chunkPath');
        }
        final bytes = await chunkFile.readAsBytes();
        await raf.writeFrom(bytes);
      }

      await raf.close();
      await File(tmpPath).rename(outputPath);

      // Clean up chunk files
      for (int i = 0; i < totalChunks; i++) {
        final chunkPath = '$mediaDir/${FileUtils.chunkFileName(i)}';
        try {
          await File(chunkPath).delete();
        } catch (_) {}
      }

      Logger.info('Merged $totalChunks chunks into $outputPath');
      return outputPath;
    } catch (e) {
      await raf.close();
      try {
        await File(tmpPath).delete();
      } catch (_) {}
      rethrow;
    }
  }
}
