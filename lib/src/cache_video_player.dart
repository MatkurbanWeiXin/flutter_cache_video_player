import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_video_player/src/data/tables.dart';
import 'package:tostore/tostore.dart';
import 'core/constants.dart';
import 'core/logger.dart';
import 'core/platform_detector.dart';
import 'data/cache_index_db.dart';
import 'data/repositories/cache_repository.dart';
import 'data/repositories/history_repository.dart';
import 'download/download_manager.dart';
import 'player/platform_player_factory.dart';
import 'proxy/proxy_server.dart';
import 'utils/file_utils.dart';

/// 插件主入口，负责初始化并协调所有层（数据库、下载、代理、播放、UI）。
/// Plugin main entry point responsible for initializing and coordinating all layers (DB, download, proxy, player, UI).
class FlutterCacheVideoPlayer {
  FlutterCacheVideoPlayer._();

  static final FlutterCacheVideoPlayer _instance = FlutterCacheVideoPlayer._();

  static FlutterCacheVideoPlayer get instance => _instance;

  factory FlutterCacheVideoPlayer() => _instance;

  CacheConfig? _config;

  late final CacheIndexDB _cacheDB;

  @internal
  CacheIndexDB get cacheDB => _cacheDB;

  late final CacheRepository _cacheRepo;

  @internal
  CacheRepository get cacheRepo => _cacheRepo;

  late final HistoryRepository _historyRepo;

  HistoryRepository get historyRepo => _historyRepo;

  late final DownloadManager _downloadManager;

  DownloadManager get downloadManager => _downloadManager;

  ProxyCacheServer? _proxyServer;

  late final PlatformPlayerFactory _playerFactory;

  PlatformPlayerFactory get playerFactory => _playerFactory;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  CacheConfig get config {
    return _config ?? CacheConfig();
  }

  void setConfig({required CacheConfig config}) {
    _config = config;
  }

  /// 初始化所有服务层：数据库 → 下载线程池 → 代理服务器 → 播放器。
  /// Initializes all service layers: DB → worker pool → proxy server → player.
  Future<void> initialize({ToStore? tostore}) async {
    WidgetsFlutterBinding.ensureInitialized();
    // Initialize database
    _cacheDB = CacheIndexDB.instance;

    final dbPath = PlatformDetector.isWeb ? '' : await FileUtils.getCacheDirectory();
    await _cacheDB.initDatabase(dbPath: dbPath, tostore: tostore);

    _cacheRepo = CacheRepository(_cacheDB, config);

    _historyRepo = HistoryRepository(_cacheDB);

    // Initialize download manager (no-op on Web)
    _downloadManager = DownloadManager(config: config, cacheRepo: _cacheRepo);

    await _downloadManager.init();

    // Start proxy server (Native only)
    if (PlatformDetector.isNative) {
      _proxyServer = ProxyCacheServer(
        config: config,
        cacheRepo: _cacheRepo,
        downloadManager: _downloadManager,
      );
      await _proxyServer!.start();
    }

    // Player
    _playerFactory = PlatformPlayerFactory(proxyServer: _proxyServer);
    _initialized = true;
    Logger.info('FlutterCacheVideoPlayer initialized');
  }

  static List<TableSchema> get tableSchemas => Tables.allTables;

  /// 释放所有资源并关闭服务。
  /// Disposes all resources and shuts down services.
  Future<void> dispose() async {
    await _proxyServer?.stop();
    await _downloadManager.dispose();
    await _cacheDB.close();
    _initialized = false;
  }
}
