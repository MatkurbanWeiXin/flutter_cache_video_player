import 'package:tostore/tostore.dart';
import '../../core/constants.dart';
import '../../core/logger.dart';
import '../../utils/file_utils.dart';
import '../../utils/url_hasher.dart';
import '../cache_index_db.dart';
import '../models/media_index.dart';
import '../models/chunk_bitmap.dart';

/// 缓存仓库，封装对 media_index 和 chunk_bitmap 表的 CRUD 操作。
/// Cache repository encapsulating CRUD operations on media_index and chunk_bitmap tables.
class CacheRepository {
  final CacheIndexDB _cacheDB;
  final CacheConfig _config;

  CacheRepository(this._cacheDB, this._config);

  ToStore get _db => _cacheDB.db;

  /// 根据原始 URL 查找媒体索引。
  /// Finds a media index by original URL.
  Future<MediaIndex?> findByUrl(String url) async {
    final hash = UrlHasher.hash(url);
    return findByHash(hash);
  }

  /// 根据 URL 哈希查找媒体索引。
  /// Finds a media index by URL hash.
  Future<MediaIndex?> findByHash(String hash) async {
    final result = await _db.query('media_index').whereEqual('url_hash', hash).first();
    if (result == null) return null;
    return MediaIndex.fromMap(result);
  }

  /// 创建新的媒体索引和对应的空位图（事务操作）。
  /// Creates a new media index and its empty bitmap within a transaction.
  Future<void> createMediaIndex(MediaIndex index) async {
    await _db.transaction(() async {
      await _db.insert('media_index', index.toMap());
      final bitmap = ChunkBitmap.empty(index.urlHash, index.totalChunks);
      await _db.insert('chunk_bitmap', bitmap.toMap());
    });
    Logger.info('Created media index: ${index.urlHash} (${index.totalChunks} chunks)');
  }

  /// 更新指定媒体的最近访问时间戳。
  /// Updates the last-accessed timestamp for the specified media.
  Future<void> updateLastAccessed(String urlHash) async {
    await _db
        .update('media_index', {'last_accessed': DateTime.now().millisecondsSinceEpoch})
        .where('url_hash', '=', urlHash);
  }

  /// 将指定媒体标记为已完成。
  /// Marks the specified media as fully downloaded.
  Future<void> markCompleted(String urlHash) async {
    await _db
        .update('media_index', {
          'is_completed': 1,
          'last_accessed': DateTime.now().millisecondsSinceEpoch,
        })
        .where('url_hash', '=', urlHash);
    Logger.info('Media $urlHash marked as completed');
  }

  /// 获取指定媒体的分片位图。
  /// Retrieves the chunk bitmap for the specified media.
  Future<ChunkBitmap?> getBitmap(String urlHash) async {
    final result = await _db.query('chunk_bitmap').whereEqual('url_hash', urlHash).first();
    if (result == null) return null;
    return ChunkBitmap.fromMap(result);
  }

  /// 更新分片位图及已下载字节数。
  /// Updates the bitmap and downloaded-bytes count.
  Future<void> updateBitmap(ChunkBitmap bitmap) async {
    await _db
        .update('chunk_bitmap', {
          'bitmap': bitmap.bitmap,
          'downloaded_bytes': bitmap.downloadedBytes,
        })
        .where('url_hash', '=', bitmap.urlHash);
  }

  /// 监听指定媒体位图变化的实时流。
  /// Returns a live stream of bitmap changes for the specified media.
  Stream<List<Map<String, dynamic>>> watchBitmap(String urlHash) {
    return _db.query('chunk_bitmap').whereEqual('url_hash', urlHash).watch();
  }

  /// 监听指定媒体索引变化的实时流。
  /// Returns a live stream of media index changes.
  Stream<List<Map<String, dynamic>>> watchMediaIndex(String urlHash) {
    return _db.query('media_index').whereEqual('url_hash', urlHash).watch();
  }

  /// 获取所有媒体索引，按最近访问时间降序排列。
  /// Returns all media indices sorted by last-accessed time descending.
  Future<List<MediaIndex>> getAllMedia() async {
    final results = await _db.query('media_index').orderByDesc('last_accessed');
    return results.data.map((m) => MediaIndex.fromMap(m)).toList();
  }

  /// 计算当前缓存总大小（字节）。
  /// Calculates the total cache size in bytes.
  Future<int> getTotalCacheSize() async {
    final results = await _db.query('chunk_bitmap');
    int total = 0;
    for (final r in results.data) {
      total += (r['downloaded_bytes'] as int?) ?? 0;
    }
    return total;
  }

  /// LRU 淘汰：删除最早访问的缓存以释放所需空间。
  /// LRU eviction: deletes least-recently-accessed caches to free required space.
  Future<void> evictLRU(int requiredBytes, {String? excludeHash}) async {
    final currentSize = await getTotalCacheSize();
    final maxBytes = _config.maxCacheBytes;
    var needToFree = (currentSize + requiredBytes) - maxBytes;
    if (needToFree <= 0) return;

    Logger.info('LRU eviction: need to free $needToFree bytes');

    final candidates = await _db.query('media_index').orderByAsc('last_accessed');

    for (final candidate in candidates.data) {
      if (needToFree <= 0) break;
      final index = MediaIndex.fromMap(candidate);
      if (index.urlHash == excludeHash) continue;
      await deleteMedia(index.urlHash);
      needToFree -= index.totalBytes;
      Logger.info('Evicted: ${index.urlHash}');
    }
  }

  /// 删除指定媒体的缓存数据和数据库记录。
  /// Deletes cache files and database records for the specified media.
  Future<void> deleteMedia(String urlHash) async {
    final index = await findByHash(urlHash);
    if (index != null) {
      await FileUtils.deleteDirectory(index.localDir);
    }
    await _db.transaction(() async {
      await _db.delete('chunk_bitmap').where('url_hash', '=', urlHash);
      await _db.delete('playback_history').where('url_hash', '=', urlHash);
      await _db.delete('media_index').where('url_hash', '=', urlHash);
    });
  }
}
