import 'package:flutter_cache_video_player/src/data/tables.dart';
import 'package:tostore/tostore.dart';
import '../core/logger.dart';

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
  Future<void> initDatabase({required String dbPath, ToStore? tostore}) async {
    _db =
        tostore ??
        await ToStore.open(
          dbPath: dbPath,
          dbName: 'flutter_cache_video_player',
          schemas: Tables.allTables,
        );
    Logger.info('CacheIndexDB initialized at $dbPath');
  }

  /// 关闭数据库连接。
  /// Closes the database connection.
  Future<void> close() async {
    await _db.close();
  }
}
