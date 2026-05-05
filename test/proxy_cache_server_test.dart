import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_cache_video_player/src/core/constants.dart';
import 'package:flutter_cache_video_player/src/data/cache_index_db.dart';
import 'package:flutter_cache_video_player/src/data/models/media_index.dart';
import 'package:flutter_cache_video_player/src/data/repositories/cache_repository.dart';
import 'package:flutter_cache_video_player/src/download/download_manager.dart';
import 'package:flutter_cache_video_player/src/proxy/proxy_server.dart';
import 'package:flutter_cache_video_player/src/utils/url_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProxyCacheServer', () {
    late final _ProxyTestHarness harness;
    late final List<int> slowPayload;

    setUpAll(() async {
      slowPayload = List<int>.generate(64 * 1024, (index) => index % 251);
      harness = await _ProxyTestHarness.create(
        config: CacheConfig(
          chunkSize: slowPayload.length,
          desktopWorkerCount: 1,
          mobileWorkerCount: 1,
          prefetchCount: 1,
          // 使用较小的 prefix（8KB）让"边下边播首字节延迟 < 300ms"断言依然
          // 通过——固定夹具在 120ms 时已推送 32KB > 8KB。
          // Use a small 8KB prefix so the "first byte < 300ms" assertion
          // still holds — the fixture pushes 32KB at 120ms, well above 8KB.
          proxyPrefetchBytes: 8 * 1024,
          proxyPrefetchTimeout: const Duration(seconds: 4),
        ),
        assets: <String, _FixtureAsset>{
          '/slow.mp4': _FixtureAsset(
            bytes: slowPayload,
            splitAfter: slowPayload.length ~/ 2,
            firstDelay: const Duration(milliseconds: 120),
            secondDelay: const Duration(milliseconds: 250),
          ),
          '/a.mp4': _FixtureAsset(bytes: ascii.encode('ABCDEFGH')),
          '/b.mp4': _FixtureAsset(bytes: ascii.encode('IJKLMNOP')),
          '/instant.mp4': _FixtureAsset(bytes: ascii.encode('XYZW')),
        },
      );
    });

    tearDownAll(() async {
      await harness.dispose();
    });

    test('streams range bytes before the chunk download fully completes', () async {
      final url = harness.fixture.urlFor('/slow.mp4').toString();
      final media = await harness.seedMedia(url, totalBytes: slowPayload.length);

      await harness.manager.startDownload(url, media);

      final result = await harness.fetchProxy(url, range: 'bytes=0-${slowPayload.length - 1}');

      expect(result.statusCode, HttpStatus.partialContent);
      expect(result.bytes, slowPayload);
      expect(result.firstChunkMs, lessThan(300));
      expect(result.totalMs, greaterThan(result.firstChunkMs + 100));
    });

    test(
      'retains chunk readiness for previous media sessions after switching active media',
      () async {
        final urlA = harness.fixture.urlFor('/a.mp4').toString();
        final urlB = harness.fixture.urlFor('/b.mp4').toString();
        final mediaA = await harness.seedMedia(urlA, totalBytes: 8);
        final mediaB = await harness.seedMedia(urlB, totalBytes: 8);

        await harness.manager.startDownload(urlA, mediaA);
        await harness.waitUntil(() => harness.manager.isChunkReady(0, urlHash: mediaA.urlHash));

        expect(harness.manager.isChunkReady(0, urlHash: mediaA.urlHash), isTrue);

        await harness.manager.startDownload(urlB, mediaB);

        expect(harness.manager.currentUrlHash, mediaB.urlHash);
        expect(harness.manager.isChunkReady(0, urlHash: mediaA.urlHash), isTrue);

        await harness.waitUntil(() => harness.manager.isChunkReady(0, urlHash: mediaB.urlHash));

        expect(harness.manager.isChunkReady(0, urlHash: mediaB.urlHash), isTrue);
      },
    );

    test('prefix prefetch returns immediately when chunk already on disk', () async {
      final url = harness.fixture.urlFor('/instant.mp4').toString();
      final media = await harness.seedMedia(url, totalBytes: 4);
      await harness.manager.startDownload(url, media);
      await harness.waitUntil(() => harness.manager.isChunkReady(0, urlHash: media.urlHash));

      final stopwatch = Stopwatch()..start();
      final result = await harness.fetchProxy(url, range: 'bytes=0-3');
      stopwatch.stop();

      expect(result.statusCode, HttpStatus.partialContent);
      expect(result.bytes, ascii.encode('XYZW'));
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('prefix prefetch waits for in-flight bytes before responding', () async {
      // 同一夹具：32KB 立即推 + 250ms 后再推 32KB。prefix=8KB < 32KB，
      // 因此响应应在首段抵达后立刻发出，但首字节时间 >= firstDelay。
      // Same fixture: 32KB immediately + 32KB after 250ms. With prefix=8KB
      // (< 32KB), the proxy should respond once the first segment lands;
      // first-byte time must be >= the fixture's initial delay.
      final url = harness.fixture.urlFor('/slow.mp4').toString();
      // 用一个全新 URL 字符串绕过上一个测试已注入的缓存条目。
      // Use a fresh URL string so we don't reuse the cached entry from the
      // first test.
      final freshUrl = '$url?prefix=1';
      final media = await harness.seedMedia(freshUrl, totalBytes: slowPayload.length);
      await harness.manager.startDownload(freshUrl, media);

      final result = await harness.fetchProxy(freshUrl, range: 'bytes=0-${slowPayload.length - 1}');

      expect(result.statusCode, HttpStatus.partialContent);
      expect(result.bytes, slowPayload);
      expect(result.firstChunkMs, greaterThanOrEqualTo(100));
    });

    test('client disconnect mid-stream does not raise unhandled errors', () async {
      // 模拟 AVPlayer 取消旧 Range 请求：在 worker 还没下载完前，客户端
      // 主动断开。代理应安静收尾，不抛 "Content size below specified
      // contentLength" 之类异步异常。
      // Simulates AVPlayer cancelling an old Range request: the client tears
      // the connection down before the worker finishes. The proxy should
      // wind down silently — no async "Content size below specified
      // contentLength" exception.
      final url = harness.fixture.urlFor('/slow.mp4').toString();
      final freshUrl = '$url?cancel=1';
      final media = await harness.seedMedia(freshUrl, totalBytes: slowPayload.length);
      await harness.manager.startDownload(freshUrl, media);

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(harness.proxy.proxyUrl(freshUrl)));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-${slowPayload.length - 1}');
        final response = await request.close();

        // 拿到首批字节就立刻断开；剩余字节会随 dataCompleter 等待。
        // Cancel as soon as the first byte arrives; the rest is still
        // pending the download future.
        final firstByte = Completer<void>();
        late StreamSubscription<List<int>> sub;
        sub = response.listen(
          (_) {
            if (!firstByte.isCompleted) firstByte.complete();
          },
          onError: (_) {},
          cancelOnError: true,
        );
        await firstByte.future.timeout(const Duration(seconds: 4));
        await sub.cancel();
      } finally {
        client.close(force: true);
      }

      // 给后台 worker 一些时间继续完成；只要进程没有抛错就算通过。
      // Give the background worker some time to finish; the test passes as
      // long as no async error escapes.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
  });
}

class _ProxyTestHarness {
  _ProxyTestHarness({
    required this.tempDir,
    required this.fixture,
    required this.cacheDb,
    required this.cacheRepo,
    required this.manager,
    required this.proxy,
  });

  final Directory tempDir;
  final _OriginFixture fixture;
  final CacheIndexDB cacheDb;
  final CacheRepository cacheRepo;
  final DownloadManager manager;
  final ProxyCacheServer proxy;

  static Future<_ProxyTestHarness> create({
    required CacheConfig config,
    required Map<String, _FixtureAsset> assets,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('fcvp-proxy-test-');
    final fixture = await _OriginFixture.start(assets);
    final cacheDb = CacheIndexDB.instance;
    await cacheDb.initDatabase(dbPath: tempDir.path);
    final cacheRepo = CacheRepository(cacheDb, config);
    final manager = DownloadManager(config: config, cacheRepo: cacheRepo);
    await manager.init();
    final proxy = ProxyCacheServer(config: config, cacheRepo: cacheRepo, downloadManager: manager);
    await proxy.start();
    return _ProxyTestHarness(
      tempDir: tempDir,
      fixture: fixture,
      cacheDb: cacheDb,
      cacheRepo: cacheRepo,
      manager: manager,
      proxy: proxy,
    );
  }

  Future<MediaIndex> seedMedia(
    String url, {
    required int totalBytes,
    String mimeType = 'video/mp4',
  }) async {
    final urlHash = UrlHasher.hash(url);
    final existing = await cacheRepo.findByHash(urlHash);
    if (existing != null) {
      return existing;
    }

    final localDir = Directory('${tempDir.path}/$urlHash');
    await localDir.create(recursive: true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final totalChunks = (totalBytes + manager.config.chunkSize - 1) ~/ manager.config.chunkSize;
    final media = MediaIndex(
      urlHash: urlHash,
      originalUrl: url,
      localDir: localDir.path,
      totalBytes: totalBytes,
      mimeType: mimeType,
      createdAt: now,
      lastAccessed: now,
      totalChunks: totalChunks,
    );
    await cacheRepo.createMediaIndex(media);
    return media;
  }

  Future<_ProxyFetchResult> fetchProxy(String originalUrl, {String? range}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(proxy.proxyUrl(originalUrl)));
      if (range != null) {
        request.headers.set(HttpHeaders.rangeHeader, range);
      }

      final stopwatch = Stopwatch()..start();
      final response = await request.close();
      final bytes = BytesBuilder(copy: false);
      final bodyCompleter = Completer<List<int>>();
      int? firstChunkMs;

      response.listen(
        (chunk) {
          firstChunkMs ??= stopwatch.elapsedMilliseconds;
          bytes.add(chunk);
        },
        onError: bodyCompleter.completeError,
        onDone: () => bodyCompleter.complete(bytes.takeBytes()),
        cancelOnError: true,
      );

      final body = await bodyCompleter.future;
      return _ProxyFetchResult(
        statusCode: response.statusCode,
        bytes: body,
        firstChunkMs: firstChunkMs ?? stopwatch.elapsedMilliseconds,
        totalMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> waitUntil(
    FutureOr<bool> Function() predicate, {
    Duration timeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await predicate()) {
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
    fail('Condition not met within $timeout');
  }

  Future<void> dispose() async {
    await proxy.stop();
    await manager.dispose();
    await cacheDb.close();
    await fixture.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}

class _ProxyFetchResult {
  const _ProxyFetchResult({
    required this.statusCode,
    required this.bytes,
    required this.firstChunkMs,
    required this.totalMs,
  });

  final int statusCode;
  final List<int> bytes;
  final int firstChunkMs;
  final int totalMs;
}

class _FixtureAsset {
  const _FixtureAsset({
    required this.bytes,
    this.splitAfter,
    this.firstDelay = Duration.zero,
    this.secondDelay = Duration.zero,
  });

  final List<int> bytes;
  final int? splitAfter;
  final Duration firstDelay;
  final Duration secondDelay;
}

class _OriginFixture {
  _OriginFixture._(this._server, this._assets);

  final HttpServer _server;
  final Map<String, _FixtureAsset> _assets;

  static Future<_OriginFixture> start(Map<String, _FixtureAsset> assets) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _OriginFixture._(server, assets);
    server.listen(fixture._handleRequest);
    return fixture;
  }

  Uri urlFor(String path) => Uri.parse('http://127.0.0.1:${_server.port}$path');

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final asset = _assets[request.uri.path];
    if (asset == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final slice = _sliceBytes(asset.bytes, request.headers.value(HttpHeaders.rangeHeader));
    final isPartial = slice.start != 0 || slice.end != asset.bytes.length - 1;

    request.response.statusCode = isPartial ? HttpStatus.partialContent : HttpStatus.ok;
    request.response.headers.contentType = ContentType('video', 'mp4');
    request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    request.response.headers.contentLength = slice.bytes.length;
    if (isPartial) {
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${slice.start}-${slice.end}/${asset.bytes.length}',
      );
    }

    if (request.method == 'HEAD') {
      await request.response.close();
      return;
    }

    request.response.bufferOutput = false;
    final splitAfter = asset.splitAfter?.clamp(0, slice.bytes.length);
    if (splitAfter != null && splitAfter > 0 && splitAfter < slice.bytes.length) {
      if (asset.firstDelay > Duration.zero) {
        await Future<void>.delayed(asset.firstDelay);
      }
      request.response.add(slice.bytes.sublist(0, splitAfter));
      await request.response.flush();
      if (asset.secondDelay > Duration.zero) {
        await Future<void>.delayed(asset.secondDelay);
      }
      request.response.add(slice.bytes.sublist(splitAfter));
    } else {
      if (asset.firstDelay > Duration.zero) {
        await Future<void>.delayed(asset.firstDelay);
      }
      request.response.add(slice.bytes);
    }
    await request.response.close();
  }

  _RangeSlice _sliceBytes(List<int> source, String? rangeHeader) {
    if (rangeHeader == null || rangeHeader.isEmpty) {
      return _RangeSlice(start: 0, end: source.length - 1, bytes: List<int>.from(source));
    }

    final match = RegExp(r'bytes=(\d+)-(\d+)?').firstMatch(rangeHeader);
    if (match == null) {
      return _RangeSlice(start: 0, end: source.length - 1, bytes: List<int>.from(source));
    }

    final start = int.parse(match.group(1)!);
    final end = match.group(2) == null ? source.length - 1 : int.parse(match.group(2)!);
    final safeEnd = end.clamp(start, source.length - 1);
    return _RangeSlice(start: start, end: safeEnd, bytes: source.sublist(start, safeEnd + 1));
  }
}

class _RangeSlice {
  const _RangeSlice({required this.start, required this.end, required this.bytes});

  final int start;
  final int end;
  final List<int> bytes;
}
