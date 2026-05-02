import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'core/constants.dart';
import 'core/platform_detector.dart';
import 'core/video_source.dart';
import 'data/cache_index_db.dart';
import 'data/models/video_cover_frame.dart';
import 'data/repositories/cache_repository.dart';
import 'data/repositories/history_repository.dart';
import 'download/download_manager.dart';
import 'player/native_player_controller.dart';
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

  Future<void>? _initFuture;

  late final CacheIndexDB _cacheDB;

  @internal
  CacheIndexDB get cacheDB => _cacheDB;

  late final CacheRepository _cacheRepo;

  @internal
  CacheRepository get cacheRepo => _cacheRepo;

  late final HistoryRepository _historyRepo;

  @internal
  HistoryRepository get historyRepo => _historyRepo;

  late final DownloadManager _downloadManager;

  @internal
  DownloadManager get downloadManager => _downloadManager;

  ProxyCacheServer? _proxyServer;

  late final PlatformPlayerFactory _playerFactory;

  @internal
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
  ///
  /// Idempotent: repeated calls (including concurrent ones) await the same
  /// in-flight future and never re-run initialization. This prevents
  /// `LateInitializationError`s on fields like `_cacheDB` when callers (e.g.
  /// `main()` plus a `State.initState`) accidentally invoke it twice.
  Future<void> initialize() {
    if (_initialized) return Future<void>.value();
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Initialize database
    _cacheDB = CacheIndexDB.instance;
    final dbPath = PlatformDetector.isWeb ? '' : await FileUtils.getCacheDirectory();
    await _cacheDB.initDatabase(dbPath: dbPath);
    _cacheRepo = CacheRepository(_cacheDB, config);
    _historyRepo = HistoryRepository(_cacheDB);
    _downloadManager = DownloadManager(config: config, cacheRepo: _cacheRepo);
    await _downloadManager.init();
    if (PlatformDetector.isNative) {
      _proxyServer = ProxyCacheServer(
        config: config,
        cacheRepo: _cacheRepo,
        downloadManager: _downloadManager,
      );
      await _proxyServer!.start();
    }
    _playerFactory = PlatformPlayerFactory(proxyServer: _proxyServer);
    _initialized = true;
  }

  static const MethodChannel _playerChannel = MethodChannel('flutter_cache_video_player/player');

  /// 从任意来源的视频中抽取若干非黑的封面候选帧。
  ///
  /// * [source] 支持 [NetworkVideoSource] / [FileVideoSource] / [AssetVideoSource]。
  ///   asset 在这里会被抽取到临时目录后再交给原生端解码。
  /// * [count] 返回的候选数量上限（按亮度降序排序后截取）。
  /// * [minBrightness] 过滤阈值，低于此值的帧（接近纯黑）会被丢弃。
  /// * [outputDir] 指定 PNG 输出目录；不传则落入应用临时目录。Web 上忽略此参数。
  ///
  /// 返回按亮度降序排好的候选列表；若原生端解码失败或被过滤完则返回空列表。
  ///
  /// Extract a handful of non-black cover candidates from any [VideoSource].
  /// Results are sorted by brightness descending. Asset sources are extracted
  /// to a temp file before decoding. Returns an empty list on failure.
  Future<List<VideoCoverFrame>> extractCoverCandidates(
    VideoSource source, {
    int count = 5,
    double minBrightness = 0.08,
    String? outputDir,
  }) async {
    assert(count > 0, 'count must be > 0');
    final candidateCount = (count * 3).clamp(count, 30);
    final resolved = await source.resolveToNativeUrl();

    String dir;
    if (kIsWeb) {
      dir = '';
    } else {
      dir = outputDir ?? await _defaultCoverDir();
    }

    final raw = await _playerChannel.invokeMethod<dynamic>('extractCovers', {
      'url': resolved,
      'count': count,
      'candidates': candidateCount,
      'minBrightness': minBrightness,
      'outputDir': dir,
    });
    if (raw == null) return const <VideoCoverFrame>[];
    final list = (raw as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map(_frameFromMap)
        .whereType<VideoCoverFrame>()
        .toList();
    list.sort((a, b) => b.brightness.compareTo(a.brightness));
    return list;
  }

  static VideoCoverFrame? _frameFromMap(Map<String, dynamic> map) {
    final path = map['path'] as String?;
    final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
    final brightness = (map['brightness'] as num?)?.toDouble() ?? 0.0;
    if (path == null || path.isEmpty) return null;
    return VideoCoverFrame(
      image: XFile(path, mimeType: 'image/png'),
      position: Duration(milliseconds: positionMs),
      brightness: brightness.clamp(0.0, 1.0),
    );
  }

  static Future<String> _defaultCoverDir() async {
    final base = await getTemporaryDirectory();
    final dir = '${base.path}/flutter_cache_video_player/covers';
    return dir;
  }

  /// 在不创建播放器实例的前提下，精确获取任意 [VideoSource] 的总时长。
  ///
  /// * [NetworkVideoSource] 会走本插件的 HTTP 缓存代理——顺带把读取到的
  ///   header / chunk 填入缓存，后续 `playNetwork` 同一地址可零成本复用。
  /// * [FileVideoSource] / [AssetVideoSource] 直接读本地文件；asset 会被
  ///   惰性抽取到临时目录。
  /// * [timeout] 超时后返回 `null` 而非抛异常；失败 / 不支持同样返回 `null`。
  ///
  /// Accurately probe the total duration of any [VideoSource] **without**
  /// creating a player texture or starting playback. Network sources are
  /// piped through the local caching proxy so subsequent `playNetwork` calls
  /// for the same URL can reuse the already-fetched bytes. File / asset
  /// sources are read locally. Returns `null` on failure or timeout.
  Future<Duration?> getDuration(
    VideoSource source, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      final resolved = await source.resolveToNativeUrl();

      // Route network sources through the proxy when available so the probe
      // shares the download cache with real playback.
      String mediaUrl = resolved;
      if (source is NetworkVideoSource && !kIsWeb && _initialized && _proxyServer != null) {
        try {
          await _proxyServer!.initCache(resolved);
          mediaUrl = _proxyServer!.proxyUrl(resolved);
        } catch (_) {
          mediaUrl = resolved;
        }
      }

      final ms = await NativePlayerController.queryDuration(
        url: mediaUrl,
        timeoutMs: timeout.inMilliseconds,
      );
      if (ms == null || ms <= 0) return null;
      return Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  /// 释放所有资源并关闭服务。
  /// Disposes all resources and shuts down services.
  Future<void> dispose() async {
    await _proxyServer?.stop();
    await _downloadManager.dispose();
    await _cacheDB.close();
    _initialized = false;
    _initFuture = null;
  }
}
