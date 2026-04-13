import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
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
    final url = request.requestedUri.queryParameters['url'];
    if (url == null || url.isEmpty) {
      return Response(400, body: 'Missing url parameter');
    }

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

    // First time: HEAD request to get metadata
    if (mediaIndex == null) {
      mediaIndex = await _initMedia(originalUrl, urlHash);
      if (mediaIndex == null) {
        return Response.internalServerError(body: 'Failed to initialize media');
      }
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
          // Read from local file
          await _readLocalChunk(controller, chunkPath, mergedPath, i, readStart, readEnd);
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

    final completeSub = downloadManager.completionStream
        .where((e) => e.chunkIndex == chunkIndex)
        .listen((event) {
          if (!dataCompleter.isCompleted) dataCompleter.complete();
        });

    final failSub = downloadManager.failureStream.where((e) => e.chunkIndex == chunkIndex).listen((
      event,
    ) {
      if (!dataCompleter.isCompleted) {
        dataCompleter.completeError(Exception('Download failed: ${event.errorMessage}'));
      }
    });

    // Race-condition guard: the chunk may have completed between the bitmap
    // read in _serveChunks and the stream subscriptions above.  Re-check on
    // disk so we don't wait for an event that already fired.
    final chunkPath = '${media.localDir}/${FileUtils.chunkFileName(chunkIndex)}';
    final chunkFile = File(chunkPath);
    if (await chunkFile.exists()) {
      if (!dataCompleter.isCompleted) dataCompleter.complete();
    }

    try {
      await dataCompleter.future.timeout(const Duration(seconds: 30));

      // 下载完成后，直接从磁盘读取精确字节范围。
      // After download completes, read the exact byte range from disk.
      final file = File(chunkPath);
      if (await file.exists()) {
        final raf = await file.open(mode: FileMode.read);
        try {
          await raf.setPosition(readStart);
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
      await completeSub.cancel();
      await failSub.cancel();
    }
  }

  Future<MediaIndex?> _initMedia(String url, String urlHash) async {
    try {
      final httpClient = HttpClient();
      final request = await httpClient.headUrl(Uri.parse(url));
      final response = await request.close();

      final contentLength = response.contentLength;
      if (contentLength <= 0) {
        Logger.error('Cannot determine content length for $url');
        return null;
      }

      final contentType = response.headers.contentType;
      String mimeType;
      if (contentType != null && contentType.mimeType != 'application/octet-stream') {
        mimeType = contentType.mimeType;
      } else {
        mimeType = MimeDetector.detect(url);
      }

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

      httpClient.close();
      return mediaIndex;
    } catch (e, st) {
      Logger.error('Failed to init media: $url', e, st);
      return null;
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

  /// 停止本地 HTTP 服务器。
  /// Stops the local HTTP server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    Logger.info('ProxyCacheServer stopped');
  }
}
