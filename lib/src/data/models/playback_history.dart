/// 播放历史模型，记录用户上次播放位置均用于断点续播。
/// Playback history model recording last play position for resume support.
class PlaybackHistory {
  final int? id;
  final String urlHash;
  final int positionMs;
  final int durationMs;
  final int playedAt;

  const PlaybackHistory({
    this.id,
    required this.urlHash,
    required this.positionMs,
    required this.durationMs,
    required this.playedAt,
  });

  /// 序列化为 Map 以存入数据库。
  /// Serializes to a Map for database storage.
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'url_hash': urlHash,
    'position_ms': positionMs,
    'duration_ms': durationMs,
    'played_at': playedAt,
  };

  static int _toInt(dynamic v) => v is int ? v : int.parse(v.toString());
  static int? _toIntOrNull(dynamic v) =>
      v == null ? null : (v is int ? v : int.tryParse(v.toString()));

  /// 从数据库 Map 反序列化。
  /// Deserializes from a database Map.
  factory PlaybackHistory.fromMap(Map<String, dynamic> map) => PlaybackHistory(
    id: _toIntOrNull(map['id']),
    urlHash: map['url_hash'] as String,
    positionMs: _toInt(map['position_ms']),
    durationMs: _toInt(map['duration_ms']),
    playedAt: _toInt(map['played_at']),
  );
}
