import 'dart:typed_data';

/// 分片位图模型，用位运算追踪每个分片的下载完成状态。
/// Chunk bitmap model tracking each chunk's completion status via bitwise operations.
class ChunkBitmap {
  final String urlHash;
  final Uint8List bitmap;
  final int downloadedBytes;

  ChunkBitmap({required this.urlHash, required this.bitmap, this.downloadedBytes = 0});

  /// 创建一个全空的位图，所有分片标记为未完成。
  /// Creates an empty bitmap with all chunks marked incomplete.
  factory ChunkBitmap.empty(String urlHash, int totalChunks) {
    final byteCount = (totalChunks + 7) ~/ 8;
    return ChunkBitmap(urlHash: urlHash, bitmap: Uint8List(byteCount));
  }

  /// 检查指定索引的分片是否已完成。
  /// Checks whether the chunk at the given index is completed.
  bool isChunkCompleted(int index) {
    final byteIndex = index ~/ 8;
    final bitIndex = index % 8;
    if (byteIndex >= bitmap.length) return false;
    return (bitmap[byteIndex] & (1 << bitIndex)) != 0;
  }

  /// 将指定分片标记为已完成，返回新的不可变位图。
  /// Marks the specified chunk as completed and returns a new immutable bitmap.
  ChunkBitmap setChunkCompleted(int index, int chunkBytes) {
    final newBitmap = Uint8List.fromList(bitmap);
    final byteIndex = index ~/ 8;
    final bitIndex = index % 8;
    if (byteIndex < newBitmap.length) {
      newBitmap[byteIndex] |= (1 << bitIndex);
    }
    return ChunkBitmap(
      urlHash: urlHash,
      bitmap: newBitmap,
      downloadedBytes: downloadedBytes + chunkBytes,
    );
  }

  /// 返回已完成的分片总数。
  /// Returns the total number of completed chunks.
  int get completedChunkCount {
    int count = 0;
    for (int i = 0; i < bitmap.length; i++) {
      int byte = bitmap[i];
      while (byte > 0) {
        count += byte & 1;
        byte >>= 1;
      }
    }
    return count;
  }

  /// 返回所有未完成分片的索引列表。
  /// Returns a list of indices for all incomplete chunks.
  List<int> getIncompleteChunks(int totalChunks) {
    final result = <int>[];
    for (int i = 0; i < totalChunks; i++) {
      if (!isChunkCompleted(i)) result.add(i);
    }
    return result;
  }

  /// 计算下载进度百分比（0.0 ~ 1.0）。
  /// Calculates the download progress ratio (0.0 – 1.0).
  double getProgress(int totalChunks) {
    if (totalChunks == 0) return 0.0;
    return completedChunkCount / totalChunks;
  }

  /// 序列化为 Map 以存入数据库。
  /// Serializes to a Map for database storage.
  Map<String, dynamic> toMap() => {
    'url_hash': urlHash,
    'bitmap': bitmap,
    'downloaded_bytes': downloadedBytes,
  };

  /// 从数据库 Map 反序列化。
  /// Deserializes from a database Map.
  factory ChunkBitmap.fromMap(Map<String, dynamic> map) => ChunkBitmap(
    urlHash: map['url_hash'] as String,
    bitmap: map['bitmap'] is Uint8List
        ? map['bitmap'] as Uint8List
        : Uint8List.fromList(List<int>.from(map['bitmap'])),
    downloadedBytes: map['downloaded_bytes'] is int
        ? map['downloaded_bytes'] as int
        : int.tryParse(map['downloaded_bytes']?.toString() ?? '') ?? 0,
  );
}
