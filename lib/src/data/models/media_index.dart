/// 媒体索引模型，持久化一个视频/音频资源的元数据。
/// Media index model persisting metadata for a single video/audio resource.
class MediaIndex {
  final String urlHash;
  final String originalUrl;
  final String localDir;
  final int totalBytes;
  final String mimeType;
  final bool isCompleted;
  final int createdAt;
  final int lastAccessed;
  final int totalChunks;

  const MediaIndex({
    required this.urlHash,
    required this.originalUrl,
    required this.localDir,
    required this.totalBytes,
    required this.mimeType,
    this.isCompleted = false,
    required this.createdAt,
    required this.lastAccessed,
    required this.totalChunks,
  });

  /// 创建副本并可选覆盖 isCompleted 或 lastAccessed。
  /// Creates a copy with optionally overridden isCompleted or lastAccessed.
  MediaIndex copyWith({bool? isCompleted, int? lastAccessed}) {
    return MediaIndex(
      urlHash: urlHash,
      originalUrl: originalUrl,
      localDir: localDir,
      totalBytes: totalBytes,
      mimeType: mimeType,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      totalChunks: totalChunks,
    );
  }

  /// 序列化为 Map 以存入数据库。
  /// Serializes to a Map for database storage.
  Map<String, dynamic> toMap() => {
    'url_hash': urlHash,
    'original_url': originalUrl,
    'local_dir': localDir,
    'total_bytes': totalBytes,
    'mime_type': mimeType,
    'is_completed': isCompleted ? 1 : 0,
    'created_at': createdAt,
    'last_accessed': lastAccessed,
    'total_chunks': totalChunks,
  };

  static int _toInt(dynamic v) => v is int ? v : int.parse(v.toString());

  /// 从数据库 Map 反序列化。
  /// Deserializes from a database Map.
  factory MediaIndex.fromMap(Map<String, dynamic> map) => MediaIndex(
    urlHash: map['url_hash'] as String,
    originalUrl: map['original_url'] as String,
    localDir: map['local_dir'] as String,
    totalBytes: _toInt(map['total_bytes']),
    mimeType: map['mime_type'] as String,
    isCompleted: _toInt(map['is_completed']) == 1,
    createdAt: _toInt(map['created_at']),
    lastAccessed: _toInt(map['last_accessed']),
    totalChunks: _toInt(map['total_chunks']),
  );
}
