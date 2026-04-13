import 'package:flutter/material.dart';
import 'core/constants.dart';
import 'core/logger.dart';
import 'core/platform_detector.dart';
import 'data/cache_index_db.dart';
import 'data/repositories/cache_repository.dart';
import 'data/repositories/history_repository.dart';
import 'download/download_manager.dart';
import 'player/flutter_cache_video_player_controller.dart';
import 'player/platform_player_factory.dart';
import 'player/flutter_cache_video_playlist_controller.dart';
import 'proxy/proxy_server.dart';
import 'utils/file_utils.dart';

/// 插件主入口，负责初始化并协调所有层（数据库、下载、代理、播放、UI）。
/// Plugin main entry point responsible for initializing and coordinating all layers (DB, download, proxy, player, UI).
class FlutterCacheVideoPlayer {
  final CacheConfig config;
  late final CacheIndexDB _cacheDB;
  late final CacheRepository cacheRepo;
  late final HistoryRepository historyRepo;
  late final DownloadManager downloadManager;
  ProxyCacheServer? proxyServer;
  late final PlatformPlayerFactory playerFactory;
  late final FlutterCacheVideoPlayerController controller;
  late final FlutterCacheVideoPlaylistController playlistController;

  bool _initialized = false;

  FlutterCacheVideoPlayer({this.config = const CacheConfig()});

  bool get isInitialized => _initialized;

  /// 初始化所有服务层：数据库 → 下载线程池 → 代理服务器 → 播放器。
  /// Initializes all service layers: DB → worker pool → proxy server → player.
  Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Initialize database
    _cacheDB = CacheIndexDB.instance;
    final dbPath = PlatformDetector.isWeb ? '' : await FileUtils.getCacheDirectory();
    await _cacheDB.init(dbPath);

    cacheRepo = CacheRepository(_cacheDB, config);
    historyRepo = HistoryRepository(_cacheDB);

    // Initialize download manager (no-op on Web)
    downloadManager = DownloadManager(config: config, cacheRepo: cacheRepo);
    await downloadManager.init();

    // Start proxy server (Native only)
    if (PlatformDetector.isNative) {
      proxyServer = ProxyCacheServer(
        config: config,
        cacheRepo: cacheRepo,
        downloadManager: downloadManager,
      );
      await proxyServer!.start();
    }

    // Player
    playerFactory = PlatformPlayerFactory(proxyServer: proxyServer);
    controller = FlutterCacheVideoPlayerController(
      config: config,
      playerFactory: playerFactory,
      cacheRepo: cacheRepo,
      historyRepo: historyRepo,
      downloadManager: downloadManager,
    );
    await controller.init();

    playlistController = FlutterCacheVideoPlaylistController(
      controller: controller,
      config: config,
    );

    _initialized = true;
    Logger.info('CacheVideoPlayerApp initialized');
  }

  /// 释放所有资源并关闭服务。
  /// Disposes all resources and shuts down services.
  Future<void> dispose() async {
    await controller.dispose();
    playlistController.dispose();
    await proxyServer?.stop();
    await downloadManager.dispose();
    await _cacheDB.close();
    _initialized = false;
  }
}
