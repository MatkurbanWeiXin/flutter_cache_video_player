import 'package:tostore/tostore.dart';
import '../cache_index_db.dart';
import '../models/playback_history.dart';
import '../tables.dart';

/// 播放历史仓库，管理断点续播位置的持久化。
/// History repository managing persistence of resume-playback positions.
class HistoryRepository {
  final CacheIndexDB _cacheDB;

  HistoryRepository(this._cacheDB);

  ToStore get _db => _cacheDB.db;

  /// 保存或更新播放位置。
  /// Saves or updates the playback position.
  Future<void> savePosition(String urlHash, int positionMs, int durationMs) async {
    final existing = await _db
        .query(TableName.playbackHistory)
        .whereEqual('url_hash', urlHash)
        .first();
    if (existing != null) {
      await _db
          .update(TableName.playbackHistory, {
            'position_ms': positionMs,
            'duration_ms': durationMs,
            'played_at': DateTime.now().millisecondsSinceEpoch,
          })
          .where('url_hash', '=', urlHash);
    } else {
      await _db.insert(TableName.playbackHistory, {
        'url_hash': urlHash,
        'position_ms': positionMs,
        'duration_ms': durationMs,
        'played_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// 获取指定媒体的最近播放位置。
  /// Retrieves the last playback position for the specified media.
  Future<PlaybackHistory?> getLastPosition(String urlHash) async {
    final result = await _db
        .query(TableName.playbackHistory)
        .whereEqual('url_hash', urlHash)
        .first();
    if (result == null) return null;
    return PlaybackHistory.fromMap(result);
  }

  /// 获取最近播放历史列表。
  /// Returns a list of recent playback history entries.
  Future<List<PlaybackHistory>> getRecentHistory({int limit = 50}) async {
    final results = await _db
        .query(TableName.playbackHistory)
        .orderByDesc('played_at')
        .limit(limit);
    return results.data.map((m) => PlaybackHistory.fromMap(m)).toList();
  }

  /// 删除指定媒体的播放历史。
  /// Deletes playback history for the specified media.
  Future<void> deleteHistory(String urlHash) async {
    await _db.delete(TableName.playbackHistory).where('url_hash', '=', urlHash);
  }

  /// 清空所有播放历史。
  /// Clears all playback history records.
  Future<void> clearAll() async {
    await _db.clear(TableName.playbackHistory);
  }
}
