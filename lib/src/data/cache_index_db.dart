import 'package:tostore/tostore.dart';
import '../core/logger.dart';

const _mediaIndexSchema = TableSchema(
  name: 'media_index',
  tableId: 'media_index',
  primaryKeyConfig: PrimaryKeyConfig(name: 'url_hash', type: PrimaryKeyType.none),
  fields: [
    FieldSchema(name: 'original_url', type: DataType.text, nullable: false),
    FieldSchema(name: 'local_dir', type: DataType.text, nullable: false),
    FieldSchema(name: 'total_bytes', type: DataType.integer, nullable: false),
    FieldSchema(name: 'mime_type', type: DataType.text, nullable: false),
    FieldSchema(name: 'is_completed', type: DataType.integer, defaultValue: 0),
    FieldSchema(name: 'created_at', type: DataType.integer, nullable: false),
    FieldSchema(name: 'last_accessed', type: DataType.integer, nullable: false),
    FieldSchema(name: 'total_chunks', type: DataType.integer, nullable: false),
  ],
);

const _chunkBitmapSchema = TableSchema(
  name: 'chunk_bitmap',
  tableId: 'chunk_bitmap',
  primaryKeyConfig: PrimaryKeyConfig(name: 'url_hash', type: PrimaryKeyType.none),
  fields: [
    FieldSchema(name: 'bitmap', type: DataType.blob, nullable: false),
    FieldSchema(name: 'downloaded_bytes', type: DataType.integer, defaultValue: 0),
  ],
);

const _playbackHistorySchema = TableSchema(
  name: 'playback_history',
  tableId: 'playback_history',
  primaryKeyConfig: PrimaryKeyConfig(name: 'id', type: PrimaryKeyType.sequential),
  fields: [
    FieldSchema(name: 'url_hash', type: DataType.text, nullable: false, createIndex: true),
    FieldSchema(name: 'position_ms', type: DataType.integer, nullable: false),
    FieldSchema(name: 'duration_ms', type: DataType.integer, nullable: false),
    FieldSchema(name: 'played_at', type: DataType.integer, nullable: false),
  ],
);

const _settingsSchema = TableSchema(
  name: 'settings',
  tableId: 'settings',
  primaryKeyConfig: PrimaryKeyConfig(name: 'key', type: PrimaryKeyType.none),
  fields: [FieldSchema(name: 'value', type: DataType.text, nullable: true)],
);

/// 缓存数据库单例，负责初始化 ToStore 及注册所有表结构。
/// Cache database singleton responsible for ToStore initialization and schema registration.
class CacheIndexDB {
  static CacheIndexDB? _instance;
  late final ToStore _db;

  CacheIndexDB._();

  /// 获取单例实例。
  /// Returns the singleton instance.
  static CacheIndexDB get instance {
    _instance ??= CacheIndexDB._();
    return _instance!;
  }

  /// 获取底层 ToStore 数据库引擎。
  /// Returns the underlying ToStore database engine.
  ToStore get db => _db;

  /// 初始化数据库，创建所有必需的表。
  /// Initializes the database and creates all required tables.
  Future<void> init(String dbPath) async {
    _db = await ToStore.open(
      dbPath: dbPath,
      dbName: 'cache_video_player',
      schemas: [_mediaIndexSchema, _chunkBitmapSchema, _playbackHistorySchema, _settingsSchema],
    );
    Logger.info('CacheIndexDB initialized at $dbPath');
  }

  /// 关闭数据库连接。
  /// Closes the database connection.
  Future<void> close() async {
    await _db.close();
  }
}
