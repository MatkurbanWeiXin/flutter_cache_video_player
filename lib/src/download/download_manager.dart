import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:signals_flutter/signals_flutter.dart';
import '../core/constants.dart';
import '../core/platform_detector.dart';
import '../data/models/media_index.dart';
import '../data/models/chunk_bitmap.dart';
import '../data/repositories/cache_repository.dart';
import '../utils/file_utils.dart';
import 'download_task.dart';
import 'download_worker_pool.dart';
import 'chunk_merger.dart';

int _compareDownloadTasks(DownloadTask a, DownloadTask b) {
  final cmp = a.priority.index.compareTo(b.priority.index);
  if (cmp != 0) return cmp;
  return a.chunkIndex.compareTo(b.chunkIndex);
}

class _DownloadSession {
  _DownloadSession({required this.media, required this.bitmap})
    : taskQueue = SplayTreeSet<DownloadTask>(_compareDownloadTasks);

  MediaIndex media;
  ChunkBitmap bitmap;
  final SplayTreeSet<DownloadTask> taskQueue;
  final Map<int, int> retryCount = <int, int>{};
}

/// 下载管理器，负责任务调度、优先级队列、重试与合并。
/// Download manager handling task scheduling, priority queueing, retries, and chunk merging.
class DownloadManager {
  final CacheConfig config;

  final CacheRepository cacheRepo;

  late final DownloadWorkerPool _pool;

  void Function()? _eventEffectDisposer;
  StreamSubscription<ChunkProgress>? _progressSubscription;
  final _progressController = StreamController<ChunkProgress>.broadcast(sync: true);

  String? _currentUrlHash;
  final Map<String, _DownloadSession> _sessions = <String, _DownloadSession>{};

  /// 当前正在下载的媒体 URL 哈希，切换视频后会更新。
  /// The URL hash of the currently downloading media; updated on video switch.
  String? get currentUrlHash => _currentUrlHash;

  /// 当前下载会话对应的媒体哈希信号，用于让代理层在切源时快速失效旧等待。
  /// Signal carrying the currently active download session's media hash so
  /// proxy waiters can fail fast when playback switches to another source.
  final activeUrlHash = signal<String?>(null);

  final latestCompletion = signal<ChunkCompleted?>(null);

  final latestFailure = signal<ChunkFailed?>(null);

  Stream<ChunkProgress> get progressStream => _progressController.stream;

  DownloadManager({required this.config, required this.cacheRepo});

  _DownloadSession? get _activeSession => _sessionFor(_currentUrlHash);

  _DownloadSession? _sessionFor(String? urlHash) {
    if (urlHash == null) return null;
    return _sessions[urlHash];
  }

  /// 初始化工作线程池并监听 Worker 事件（Web 平台跳过）。
  /// Initializes the worker pool and subscribes to worker events (skipped on web).
  Future<void> init() async {
    if (PlatformDetector.isWeb) return;

    final workerCount = PlatformDetector.isMobile
        ? config.mobileWorkerCount
        : config.desktopWorkerCount;

    _pool = DownloadWorkerPool(workerCount: workerCount, config: config);
    await _pool.start();

    _eventEffectDisposer = effect(() {
      final event = _pool.latestEvent.value;
      if (event == null) return;
      _onWorkerEvent(event);
    });
    _progressSubscription = _pool.progressStream.listen(_onChunkProgress);
  }

  void _onChunkProgress(ChunkProgress event) {
    _progressController.add(event);
  }

  void _onWorkerEvent(WorkerEvent event) {
    switch (event) {
      case ChunkProgress():
        // 进度事件已在 WorkerPool 层过滤，不再传播到信号链。
        // Progress events are filtered at the WorkerPool layer.
        break;
      case ChunkCompleted():
        _onChunkCompleted(event);
        break;
      case ChunkFailed():
        _onChunkFailed(event);
        break;
      case WorkerReady():
        _dispatchNext();
        break;
      case WorkerCancelled(:final urlHash, :final chunkIndex):
        // 向 failureSignal 发送事件，以解除 _downloadAndStream 中等待的 Completer。
        // Emit failure so that _downloadAndStream completers are unblocked.
        latestFailure.set(
          ChunkFailed(
            urlHash: urlHash,
            chunkIndex: chunkIndex,
            errorMessage: 'Download cancelled (media switched)',
            retryable: false,
          ),
          force: true,
        );
        _dispatchNext();
        break;
    }
  }

  Future<void> _onChunkCompleted(ChunkCompleted event) async {
    latestCompletion.set(event, force: true);
    final session = _sessionFor(event.urlHash);
    if (session == null) {
      _dispatchNext();
      return;
    }
    session.retryCount.remove(event.chunkIndex);

    // Update bitmap
    session.bitmap = session.bitmap.setChunkCompleted(event.chunkIndex, event.bytesWritten);
    await cacheRepo.updateBitmap(session.bitmap);

    // Check if all chunks complete
    final incomplete = session.bitmap.getIncompleteChunks(session.media.totalChunks);
    if (incomplete.isEmpty) {
      await cacheRepo.markCompleted(event.urlHash);
      session.media = session.media.copyWith(
        isCompleted: true,
        lastAccessed: DateTime.now().millisecondsSinceEpoch,
      );

      // Trigger merge
      _mergeInBackground(session);
    } else if (event.urlHash == _currentUrlHash) {
      session.media = session.media.copyWith(lastAccessed: DateTime.now().millisecondsSinceEpoch);
    }

    _dispatchNext();
  }

  void _onChunkFailed(ChunkFailed event) {
    latestFailure.set(event, force: true);

    final session = _sessionFor(event.urlHash);
    if (session == null) {
      _dispatchNext();
      return;
    }

    if (event.retryable) {
      final count = session.retryCount[event.chunkIndex] ?? 0;
      if (count < config.maxRetryCount) {
        session.retryCount[event.chunkIndex] = count + 1;
        final delayMs = config.retryBaseDelayMs * (1 << count);
        Future.delayed(Duration(milliseconds: delayMs), () {
          _resubmitChunk(event.urlHash, event.chunkIndex);
        });
        return;
      }
    }
    _dispatchNext();
  }

  void _resubmitChunk(String urlHash, int chunkIndex) {
    final session = _sessionFor(urlHash);
    if (session == null) return;
    final task = _createTask(session, chunkIndex, TaskPriority.p0Urgent);
    if (task != null) {
      session.taskQueue.add(task);
      if (urlHash == _currentUrlHash) {
        _dispatchNext();
      }
    }
  }

  /// 开始下载指定媒体的所有未完成分片。
  /// Starts downloading all incomplete chunks for the specified media.
  Future<void> startDownload(String url, MediaIndex media) async {
    if (PlatformDetector.isWeb) return;

    // 切换媒体时立即取消旧任务，释放 Worker 供新媒体使用。
    // Cancel existing downloads immediately to free workers for the new media.
    _pool.cancelAll();

    // 重置信号，避免残留值被新的 effect 监听器误读。
    // Reset signals so stale values from the previous session are not
    // misread by newly created effect listeners in the proxy server.
    latestCompletion.value = null;
    latestFailure.value = null;

    _currentUrlHash = media.urlHash;
    activeUrlHash.value = media.urlHash;
    final bitmap = await cacheRepo.getBitmap(media.urlHash);
    if (bitmap == null) return;

    final session = _sessions.update(media.urlHash, (existing) {
      existing.media = media;
      existing.bitmap = bitmap;
      existing.taskQueue.clear();
      existing.retryCount.clear();
      return existing;
    }, ifAbsent: () => _DownloadSession(media: media, bitmap: bitmap));
    session.taskQueue.clear();
    session.retryCount.clear();

    if (media.isCompleted) return;

    // Queue background fill
    final incomplete = session.bitmap.getIncompleteChunks(media.totalChunks);
    for (final idx in incomplete) {
      final task = _createTask(session, idx, TaskPriority.p3Low);
      if (task != null) session.taskQueue.add(task);
    }

    _dispatchNext();
  }

  /// 处理 Seek 操作：重建任务队列，优先下载目标分片。
  /// Handles seek: rebuilds the task queue with the target chunk at highest priority.
  void onSeek(int byteOffset) {
    final session = _activeSession;
    if (session == null) return;

    final targetChunk = byteOffset ~/ config.chunkSize;

    // Cancel non-critical tasks
    _pool.cancelAll();

    // Rebuild queue with new priorities
    session.taskQueue.clear();

    final incomplete = session.bitmap.getIncompleteChunks(session.media.totalChunks);

    for (final idx in incomplete) {
      TaskPriority priority;
      if (idx == targetChunk) {
        priority = TaskPriority.p0Urgent;
      } else if (idx > targetChunk && idx <= targetChunk + config.prefetchCount) {
        priority = TaskPriority.p1High;
      } else {
        priority = TaskPriority.p3Low;
      }
      final task = _createTask(session, idx, priority);
      if (task != null) session.taskQueue.add(task);
    }

    _dispatchNext();
  }

  /// 将指定分片提升为最高优先级。
  /// Promotes the specified chunk to the highest priority.
  void requestChunkPriority(int chunkIndex, {String? urlHash}) {
    final targetUrlHash = urlHash ?? _currentUrlHash;
    if (targetUrlHash == null || targetUrlHash != _currentUrlHash) return;
    final session = _sessionFor(targetUrlHash);
    if (session == null) return;
    if (session.bitmap.isChunkCompleted(chunkIndex)) return;

    // Check if already being downloaded
    if (_pool.activeChunkIndices.contains(chunkIndex)) return;

    // Add as P0
    final task = _createTask(session, chunkIndex, TaskPriority.p0Urgent);
    if (task != null) {
      session.taskQueue.add(task);
      _dispatchNext();
    }
  }

  /// 强制使指定分片的缓存失效并重新下载。
  /// 用于处理 DB 位图与磁盘文件不一致的情况（如 chunk 文件被删但位图仍标记完成）。
  /// Invalidates a chunk whose bitmap says "complete" but whose file is missing,
  /// resets the bitmap bit, and queues an urgent re-download.
  Future<void> invalidateAndDownloadChunk(int chunkIndex, {String? urlHash}) async {
    final targetUrlHash = urlHash ?? _currentUrlHash;
    if (targetUrlHash == null || targetUrlHash != _currentUrlHash) return;
    final session = _sessionFor(targetUrlHash);
    if (session == null) return;

    // 重置该分片在位图中的完成标记。
    // Clear the completion bit for this chunk.
    final newBitmap = Uint8List.fromList(session.bitmap.bitmap);
    final byteIndex = chunkIndex ~/ 8;
    final bitIndex = chunkIndex % 8;
    if (byteIndex < newBitmap.length) {
      newBitmap[byteIndex] &= ~(1 << bitIndex);
    }
    session.bitmap = ChunkBitmap(
      urlHash: session.bitmap.urlHash,
      bitmap: newBitmap,
      downloadedBytes: session.bitmap.downloadedBytes,
    );
    await cacheRepo.updateBitmap(session.bitmap);

    // 跳过 activeChunkIndices 检查——该分片可能不在下载中。
    // Skip activeChunkIndices check — this chunk is almost certainly not active.
    final task = _createTask(session, chunkIndex, TaskPriority.p0Urgent);
    if (task != null) {
      session.taskQueue.add(task);
      _dispatchNext();
    }
  }

  DownloadTask? _createTask(_DownloadSession session, int chunkIndex, TaskPriority priority) {
    final media = session.media;
    final byteStart = chunkIndex * config.chunkSize;
    var byteEnd = byteStart + config.chunkSize - 1;
    if (byteEnd >= media.totalBytes) byteEnd = media.totalBytes - 1;

    return DownloadTask(
      url: media.originalUrl,
      urlHash: media.urlHash,
      chunkIndex: chunkIndex,
      byteStart: byteStart,
      byteEnd: byteEnd,
      savePath: '${media.localDir}/${FileUtils.chunkFileName(chunkIndex)}',
      priority: priority,
    );
  }

  void _dispatchNext() {
    final session = _activeSession;
    if (session == null) return;

    while (_pool.hasAvailableWorker && session.taskQueue.isNotEmpty) {
      final task = session.taskQueue.first;
      session.taskQueue.remove(task);

      // Skip already completed
      if (session.bitmap.isChunkCompleted(task.chunkIndex)) {
        continue;
      }
      // Skip already in progress
      if (_pool.activeChunkIndices.contains(task.chunkIndex)) {
        continue;
      }

      _pool.submitTask(task);
    }
  }

  Future<void> _mergeInBackground(_DownloadSession session) async {
    try {
      await ChunkMerger.mergeChunks(
        mediaDir: session.media.localDir,
        totalChunks: session.media.totalChunks,
      );
    } catch (_) {}
  }

  /// 取消所有下载并清空队列。
  /// Cancels all active downloads and clears the task queue.
  void cancelAll() {
    _pool.cancelAll();
    for (final session in _sessions.values) {
      session.taskQueue.clear();
      session.retryCount.clear();
    }
  }

  /// 检查指定分片是否已下载完成。
  /// Checks whether the specified chunk has been downloaded.
  bool isChunkReady(int chunkIndex, {String? urlHash}) {
    final session = _sessionFor(urlHash ?? _currentUrlHash);
    return session?.bitmap.isChunkCompleted(chunkIndex) ?? false;
  }

  bool isActiveMedia(String urlHash) => _currentUrlHash == urlHash;

  /// 等待指定分片至少有 [prefixBytes] 字节落盘（或全部完成）。
  ///
  /// 用于本地代理在响应 Range 请求前先确保有少量字节可读，避免 AVPlayer
  /// 等待空响应过久而触发 OSStatus -12848 等首字节超时类错误。
  ///
  /// * 已完成 / 合并文件已存在 → 立即返回。
  /// * 等待期间下载失败或分片被取消 → 抛出异常。
  /// * 超时 → 静默返回，让调用方继续走原有边下边播路径。
  ///
  /// Awaits at least [prefixBytes] bytes of [chunkIndex] to be persisted on
  /// disk (or full completion). Returns silently on timeout. Throws on
  /// failure / cancellation so the proxy can fall back gracefully.
  Future<void> ensureChunkPrefix(
    String urlHash,
    int chunkIndex, {
    required int prefixBytes,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (PlatformDetector.isWeb) return;
    if (prefixBytes <= 0) return;

    final session = _sessionFor(urlHash);
    if (session == null) return;

    // 已完成 → 已经在磁盘上。
    // Already done — bytes are on disk.
    if (session.bitmap.isChunkCompleted(chunkIndex)) return;

    // 合并文件存在意味着旧会话已经写出全部字节，直接返回。
    // Merged file exists → all bytes already on disk; nothing to wait for.
    final mergedPath = '${session.media.localDir}/${FileUtils.mergedFileName()}';
    if (await File(mergedPath).exists()) return;

    // 上限：分片本身大小（最后一个分片可能比 chunkSize 小）。
    // Cap at the actual chunk size (last chunk may be shorter than chunkSize).
    final byteStart = chunkIndex * config.chunkSize;
    final maxChunkBytes = (session.media.totalBytes - byteStart).clamp(0, config.chunkSize);
    if (maxChunkBytes == 0) return;
    final target = prefixBytes < maxChunkBytes ? prefixBytes : maxChunkBytes;

    // 提升优先级，确保 worker 立刻开下载。
    // Promote to P0 so the worker starts immediately.
    requestChunkPriority(chunkIndex, urlHash: urlHash);

    final completer = Completer<void>();
    var streamed = 0;
    StreamSubscription<ChunkProgress>? sub;
    void Function()? completeDisposer;
    void Function()? failDisposer;

    void finishOk() {
      if (!completer.isCompleted) completer.complete();
    }

    void finishErr(Object err) {
      if (!completer.isCompleted) completer.completeError(err);
    }

    sub = progressStream.listen((event) {
      if (event.urlHash != urlHash || event.chunkIndex != chunkIndex) return;
      streamed = event.downloadedBytes;
      if (streamed >= target) finishOk();
    });

    var completeInitial = true;
    completeDisposer = effect(() {
      final e = latestCompletion.value;
      if (completeInitial) {
        completeInitial = false;
        return;
      }
      if (e != null && e.urlHash == urlHash && e.chunkIndex == chunkIndex) {
        finishOk();
      }
    });

    var failInitial = true;
    failDisposer = effect(() {
      final e = latestFailure.value;
      if (failInitial) {
        failInitial = false;
        return;
      }
      if (e != null && e.urlHash == urlHash && e.chunkIndex == chunkIndex) {
        finishErr(StateError('Prefix prefetch failed: ${e.errorMessage}'));
      }
    });

    // 进入等待前再做一次磁盘检查，规避位图刚刚被更新但 effect 尚未观测的竞态。
    // Re-check the bitmap / disk before waiting to dodge the race where the
    // chunk completed between our entry checks and subscription setup.
    if (session.bitmap.isChunkCompleted(chunkIndex)) {
      finishOk();
    } else if (await File(mergedPath).exists()) {
      finishOk();
    }

    try {
      await completer.future.timeout(
        timeout,
        onTimeout: () {
          // 静默忽略——调用方继续走原有路径。
          // Swallow timeout — caller continues with the original code path.
          return;
        },
      );
    } finally {
      await sub.cancel();
      completeDisposer();
      failDisposer();
    }
  }

  ChunkBitmap? get currentBitmap => _activeSession?.bitmap;

  /// 释放资源，关闭工作池和所有事件流。
  /// Disposes resources, shutting down the pool and all event streams.
  Future<void> dispose() async {
    cancelAll();
    _eventEffectDisposer?.call();
    await _progressSubscription?.cancel();
    await _progressController.close();
    activeUrlHash.value = null;
    _currentUrlHash = null;
    _sessions.clear();
    await _pool.shutdown();
  }
}
