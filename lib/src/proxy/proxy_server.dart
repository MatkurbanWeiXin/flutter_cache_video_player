import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:signals/signals.dart';
import '../core/constants.dart';
import '../core/logger.dart';
import '../data/models/media_index.dart';
import '../data/models/chunk_bitmap.dart';
import '../data/repositories/cache_repository.dart';
import '../download/download_manager.dart';
import '../utils/file_utils.dart';
import '../utils/url_hasher.dart';
import 'range_handler.dart';
import 'mime_detector.dart';

/// 本地 HTTP 代理缓存服务器，基于 shelf 为播放器提供媒体流。
/// Local HTTP proxy cache server based on shelf, serving media streams to the player.
class ProxyCacheServer {
  final CacheConfig config;
  final CacheRepository cacheRepo;
  final DownloadManager downloadManager;
  HttpServer? _server;
  int _port = 0;

  ProxyCacheServer({required this.config, required this.cacheRepo, required this.downloadManager});

  int get port => _port;
  String get baseUrl => 'http://127.0.0.1:$_port';

  /// 将原始 URL 转换为本地代理 URL。
  /// Converts an original URL into a local proxy URL.
  String proxyUrl(String originalUrl) {
    final encoded = Uri.encodeComponent(originalUrl);
    return '$baseUrl/stream?url=$encoded';
  }

  /// 启动本地 HTTP 服务器，白动分配可用端口。
  /// Starts the local HTTP server on an automatically assigned port.
  Future<void> start() async {
    final handler = const Pipeline().addHandler(_handleRequest);

    _server = await shelf_io.serve(handler, '127.0.0.1', 0);
    _port = _server!.port;
    Logger.info('ProxyCacheServer started on $baseUrl');
  }

  Future<Response> _handleRequest(Request request) async {
    // 健康检查端点，用于验证代理服务器可用。
    // Health-check endpoint to verify the proxy server is alive.
    if (request.requestedUri.path == '/ping') {
      return Response.ok('pong');
    }

    final url = request.requestedUri.queryParameters['url'];
    if (url == null || url.isEmpty) {
      return Response(400, body: 'Missing url parameter');
    }

    final rangeHeader = request.headers['range'];
    Logger.info('Proxy request: ${request.method} range=$rangeHeader');

    try {
      return await _handleStreamRequest(request, url);
    } catch (e, st) {
      Logger.error('Proxy error for $url', e, st);
      return Response.internalServerError(body: e.toString());
    }
  }

  Future<Response> _handleStreamRequest(Request request, String originalUrl) async {
    final urlHash = UrlHasher.hash(originalUrl);
    var mediaIndex = await cacheRepo.findByHash(urlHash);

    // initCache() 应已预初始化——如果仍找不到则立即返回错误，不阻塞等待远程 HTTP。
    // initCache() should have pre-initialized. If missing, return error
    // immediately instead of blocking on a remote HTTP request.
    if (mediaIndex == null) {
      Logger.error('MediaIndex not found for $originalUrl (initCache may have failed)');
      return Response(503, body: 'Media not yet initialized');
    }

    await cacheRepo.updateLastAccessed(urlHash);

    final rangeHeader = request.headers['range'];
    final range = RangeHeader.parse(rangeHeader, mediaIndex.totalBytes);

    if (range == null) {
      // No range header — serve full content with 200
      return _serveFullContent(mediaIndex);
    }

    final start = range.start;
    final end = range.resolvedEnd(mediaIndex.totalBytes);
    return _serveRange(mediaIndex, start, end);
  }

  Future<Response> _serveFullContent(MediaIndex media) async {
    final bitmap = await cacheRepo.getBitmap(media.urlHash);
    if (bitmap == null) {
      return Response.internalServerError(body: 'Bitmap not found');
    }

    final endByte = media.totalBytes - 1;
    final startChunk = 0;
    final endChunk = endByte ~/ config.chunkSize;

    final controller = StreamController<List<int>>();
    _serveChunks(controller, media, bitmap, startChunk, endChunk, 0, endByte);

    return Response.ok(
      controller.stream,
      headers: {
        'content-type': media.mimeType,
        'content-length': media.totalBytes.toString(),
        'accept-ranges': 'bytes',
      },
    );
  }

  Future<Response> _serveRange(MediaIndex media, int start, int end) async {
    final bitmap = await cacheRepo.getBitmap(media.urlHash);
    if (bitmap == null) {
      return Response.internalServerError(body: 'Bitmap not found');
    }

    final startChunk = start ~/ config.chunkSize;
    final endChunk = end ~/ config.chunkSize;

    // Build a stream that reads from local chunks or waits for download
    final controller = StreamController<List<int>>();

    _serveChunks(controller, media, bitmap, startChunk, endChunk, start, end);

    final contentLength = end - start + 1;
    return Response(
      206,
      body: controller.stream,
      headers: {
        'content-type': media.mimeType,
        'content-range': 'bytes $start-$end/${media.totalBytes}',
        'accept-ranges': 'bytes',
        'content-length': contentLength.toString(),
        'connection': 'keep-alive',
        'x-cache-status': _getCacheStatus(bitmap, startChunk, endChunk),
      },
    );
  }

  Future<void> _serveChunks(
    StreamController<List<int>> controller,
    MediaIndex media,
    ChunkBitmap bitmap,
    int startChunk,
    int endChunk,
    int rangeStart,
    int rangeEnd,
  ) async {
    try {
      for (int i = startChunk; i <= endChunk; i++) {
        final chunkPath = '${media.localDir}/${FileUtils.chunkFileName(i)}';
        final mergedPath = '${media.localDir}/${FileUtils.mergedFileName()}';

        // Calculate byte range within this chunk
        final chunkByteStart = i * config.chunkSize;
        final readStart = (i == startChunk) ? rangeStart - chunkByteStart : 0;
        final readEnd = (i == endChunk) ? rangeEnd - chunkByteStart : config.chunkSize - 1;

        if (bitmap.isChunkCompleted(i)) {
          // 尝试从本地文件读取。如果文件不存在（DB 与磁盘不一致），
          // 降级为下载路径而非直接崩溃。
          // Try reading from local file. If missing (DB/disk inconsistency),
          // fall through to the download path instead of crashing.
          final chunkExists = await File(chunkPath).exists();
          final mergedExists = !chunkExists && await File(mergedPath).exists();
          if (chunkExists || mergedExists) {
            await _readLocalChunk(controller, chunkPath, mergedPath, i, readStart, readEnd);
          } else {
            Logger.warning('Chunk $i marked complete but file missing, re-downloading');
            // 位图标记完成但文件不存在——需要先使位图失效，否则 Worker 会跳过下载。
            // Bitmap says complete but file is gone — invalidate bitmap first,
            // otherwise the download manager will skip this chunk.
            await downloadManager.invalidateAndDownloadChunk(i);
            await _downloadAndStream(controller, media, i, readStart, readEnd);
          }
        } else {
          // Request download and wait
          await _downloadAndStream(controller, media, i, readStart, readEnd);
        }
      }
      await controller.close();
    } catch (e) {
      controller.addError(e);
      await controller.close();
    }
  }

  Future<void> _readLocalChunk(
    StreamController<List<int>> controller,
    String chunkPath,
    String mergedPath,
    int chunkIndex,
    int readStart,
    int readEnd,
  ) async {
    File file = File(chunkPath);
    int offset = readStart;

    if (!await file.exists()) {
      // Try merged file
      file = File(mergedPath);
      if (!await file.exists()) {
        throw StateError('Neither chunk nor merged file exists for chunk $chunkIndex');
      }
      offset = chunkIndex * config.chunkSize + readStart;
    }

    final raf = await file.open(mode: FileMode.read);
    try {
      await raf.setPosition(offset);
      final length = readEnd - readStart + 1;
      final data = await raf.read(length);
      controller.add(data);
    } finally {
      await raf.close();
    }
  }

  Future<void> _downloadAndStream(
    StreamController<List<int>> controller,
    MediaIndex media,
    int chunkIndex,
    int readStart,
    int readEnd,
  ) async {
    // Request priority download
    downloadManager.requestChunkPriority(chunkIndex);

    // 只等待下载完成/失败，不再订阅 progressStream 收集原始字节。
    // Only wait for completion/failure — no longer subscribing to progressStream for raw bytes.
    final dataCompleter = Completer<void>();
    final expectedUrlHash = media.urlHash;

    // effect() 会立即以当前信号值执行一次。跳过首次执行以防止来自
    // 前一个下载会话的残留值误触发 Completer。
    // effect() runs immediately with the current signal value. Skip the first
    // invocation to prevent stale values from a previous download session
    // from prematurely resolving the Completer.
    var completeInitial = true;
    final completeDisposer = effect(() {
      final e = downloadManager.latestCompletion.value;
      if (completeInitial) {
        completeInitial = false;
        return;
      }
      if (downloadManager.currentUrlHash != expectedUrlHash) return;
      if (e != null && e.chunkIndex == chunkIndex && !dataCompleter.isCompleted) {
        dataCompleter.complete();
      }
    });

    var failInitial = true;
    final failDisposer = effect(() {
      final e = downloadManager.latestFailure.value;
      if (failInitial) {
        failInitial = false;
        return;
      }
      if (downloadManager.currentUrlHash != expectedUrlHash) return;
      if (e != null && e.chunkIndex == chunkIndex && !dataCompleter.isCompleted) {
        dataCompleter.completeError(Exception('Download failed: ${e.errorMessage}'));
      }
    });

    // Race-condition guard: the chunk may have completed between the bitmap
    // read in _serveChunks and the stream subscriptions above.  Re-check on
    // disk so we don't wait for an event that already fired.
    // Also check the merged file: after ChunkMerger runs, individual chunk
    // files are deleted and replaced by a single merged file.
    final chunkPath = '${media.localDir}/${FileUtils.chunkFileName(chunkIndex)}';
    final mergedPath = '${media.localDir}/${FileUtils.mergedFileName()}';
    if (await File(chunkPath).exists() || await File(mergedPath).exists()) {
      if (!dataCompleter.isCompleted) dataCompleter.complete();
    }

    try {
      await dataCompleter.future.timeout(const Duration(seconds: 15));

      // 下载完成后，直接从磁盘读取精确字节范围（支持合并文件回退）。
      // After download completes, read the exact byte range from disk (with merged file fallback).
      File file = File(chunkPath);
      int offset = readStart;

      if (!await file.exists()) {
        // 分片文件已被合并，改从合并文件读取。
        // Chunk file has been merged; read from the merged file instead.
        file = File(mergedPath);
        offset = chunkIndex * config.chunkSize + readStart;
      }

      if (await file.exists()) {
        final raf = await file.open(mode: FileMode.read);
        try {
          await raf.setPosition(offset);
          final length = readEnd - readStart + 1;
          final data = await raf.read(length);
          controller.add(data);
        } finally {
          await raf.close();
        }
      } else {
        throw StateError('Chunk file not found after download: $chunkPath');
      }
    } finally {
      completeDisposer();
      failDisposer();
    }
  }

  Future<MediaIndex?> _initMedia(String url, String urlHash) async {
    HttpClient? httpClient;
    try {
      httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..idleTimeout = const Duration(seconds: 10);

      // 优先使用 GET + Range: bytes=0-0 获取 Content-Range 来确定总大小。
      // 某些 CDN/服务器不正确支持 HEAD 请求，GET Range 更可靠。
      // Prefer GET + Range: bytes=0-0 to retrieve Content-Range for total size.
      // Some CDNs/servers don't support HEAD correctly; GET Range is more reliable.
      int contentLength = -1;
      String? mimeStr;

      try {
        final getRequest = await httpClient.getUrl(Uri.parse(url));
        getRequest.headers.set('Range', 'bytes=0-0');
        final getResponse = await getRequest.close();

        // 解析 Content-Range: bytes 0-0/TOTAL
        // Parse Content-Range: bytes 0-0/TOTAL
        final contentRange = getResponse.headers.value('content-range');
        if (contentRange != null) {
          final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
          if (match != null) {
            contentLength = int.parse(match.group(1)!);
          }
        }

        final ct = getResponse.headers.contentType;
        if (ct != null && ct.mimeType != 'application/octet-stream') {
          mimeStr = ct.mimeType;
        }

        // 消耗并丢弃响应体以释放连接。
        // Drain the response body to release the connection.
        await getResponse.drain<void>();
      } catch (e) {
        Logger.warning('GET Range failed for $url, falling back to HEAD: $e');
      }

      // 降级：使用 HEAD 请求。
      // Fallback: use HEAD request.
      if (contentLength <= 0) {
        try {
          final headRequest = await httpClient.headUrl(Uri.parse(url));
          final headResponse = await headRequest.close();
          contentLength = headResponse.contentLength;
          final ct = headResponse.headers.contentType;
          if (ct != null && ct.mimeType != 'application/octet-stream') {
            mimeStr = ct.mimeType;
          }
          await headResponse.drain<void>();
        } catch (e) {
          Logger.error('HEAD request also failed for $url: $e');
          return null;
        }
      }

      if (contentLength <= 0) {
        Logger.error('Cannot determine content length for $url');
        return null;
      }

      final mimeType = mimeStr ?? MimeDetector.detect(url);

      final localDir = await FileUtils.getMediaDir(urlHash);
      final totalChunks = (contentLength + config.chunkSize - 1) ~/ config.chunkSize;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Check if we need LRU eviction (exclude current media)
      await cacheRepo.evictLRU(contentLength, excludeHash: urlHash);

      final mediaIndex = MediaIndex(
        urlHash: urlHash,
        originalUrl: url,
        localDir: localDir,
        totalBytes: contentLength,
        mimeType: mimeType,
        createdAt: now,
        lastAccessed: now,
        totalChunks: totalChunks,
      );

      await cacheRepo.createMediaIndex(mediaIndex);
      await downloadManager.startDownload(url, mediaIndex);

      return mediaIndex;
    } on SocketException catch (e) {
      Logger.error('SocketException initializing media $url: $e');
      return null;
    } catch (e, st) {
      Logger.error('Failed to init media: $url', e, st);
      return null;
    } finally {
      httpClient?.close();
    }
  }

  String _getCacheStatus(ChunkBitmap bitmap, int startChunk, int endChunk) {
    bool allHit = true;
    bool anyHit = false;
    for (int i = startChunk; i <= endChunk; i++) {
      if (bitmap.isChunkCompleted(i)) {
        anyHit = true;
      } else {
        allHit = false;
      }
    }
    if (allHit) return 'HIT';
    if (anyHit) return 'PARTIAL';
    return 'MISS';
  }

  /// 获取已缓存的合并文件 URL（file:/// 格式），未缓存时返回 null。
  /// Returns the cached merged file URL (file:/// format), or null if not cached.
  Future<String?> getCachedFileUrl(String originalUrl) async {
    final urlHash = UrlHasher.hash(originalUrl);
    final mediaIndex = await cacheRepo.findByHash(urlHash);
    if (mediaIndex == null) return null;

    final mergedFile = File('${mediaIndex.localDir}/${FileUtils.mergedFileName()}');
    if (await mergedFile.exists()) {
      await cacheRepo.updateLastAccessed(urlHash);
      return Uri.file(mergedFile.path).toString();
    }
    return null;
  }

  /// 仅初始化缓存（创建索引并启动后台下载），不提供流服务。
  /// 失败时抛出异常以便调用方落回原始 URL。
  /// Initializes caching only (creates index and starts background download)
  /// without serving a stream. Throws on failure so caller can fall back.
  Future<void> initCache(String originalUrl) async {
    final urlHash = UrlHasher.hash(originalUrl);
    var mediaIndex = await cacheRepo.findByHash(urlHash);
    if (mediaIndex != null) {
      // iOS 调试/重装后容器 UUID 会变，DB 中存的旧绝对路径不再可用。
      // 检测路径是否有效，无效则删除旧记录从头初始化。
      // On iOS the container UUID changes between debug sessions / reinstalls.
      // Detect stale absolute paths and purge the old record so we start fresh.
      final dir = Directory(mediaIndex.localDir);
      if (!await dir.exists()) {
        Logger.warning('Stale localDir detected (${mediaIndex.localDir}), purging record');
        await cacheRepo.deleteMedia(urlHash);
        mediaIndex = null; // fall through to _initMedia below
      }
    }

    if (mediaIndex == null) {
      final result = await _initMedia(originalUrl, urlHash);
      if (result == null) {
        throw Exception('Failed to fetch media metadata for $originalUrl');
      }
    } else {
      await cacheRepo.updateLastAccessed(urlHash);
      // 确保后台下载在运行——可能是上次会话残留的记录，Worker 并未启动。
      // Ensure background download is running — this entry may be left over
      // from a previous session where workers were not started.
      await downloadManager.startDownload(originalUrl, mediaIndex);
    }
  }

  /// 停止本地 HTTP 服务器。
  /// Stops the local HTTP server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    Logger.info('ProxyCacheServer stopped');
  }
}
