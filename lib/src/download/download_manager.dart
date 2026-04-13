import 'dart:async';
import 'dart:collection';
import '../core/constants.dart';
import '../core/logger.dart';
import '../core/platform_detector.dart';
import '../data/models/media_index.dart';
import '../data/models/chunk_bitmap.dart';
import '../data/repositories/cache_repository.dart';
import '../utils/file_utils.dart';
import 'download_task.dart';
import 'download_worker_pool.dart';
import 'chunk_merger.dart';

/// 下载管理器，负责任务调度、优先级队列、重试与合并。
/// Download manager handling task scheduling, priority queueing, retries, and chunk merging.
class DownloadManager {
  final CacheConfig config;
  final CacheRepository cacheRepo;
  late final DownloadWorkerPool _pool;
  final _taskQueue = SplayTreeSet<DownloadTask>((a, b) {
    final cmp = a.priority.index.compareTo(b.priority.index);
    if (cmp != 0) return cmp;
    return a.chunkIndex.compareTo(b.chunkIndex);
  });
  StreamSubscription? _eventSub;
  String? _currentUrlHash;
  MediaIndex? _currentMedia;
  ChunkBitmap? _currentBitmap;

  final _progressController = StreamController<ChunkProgress>.broadcast();
  final _completionController = StreamController<ChunkCompleted>.broadcast();
  final _failureController = StreamController<ChunkFailed>.broadcast();
  final _mediaCompleteController = StreamController<String>.broadcast();

  Stream<ChunkProgress> get progressStream => _progressController.stream;
  Stream<ChunkCompleted> get completionStream => _completionController.stream;
  Stream<ChunkFailed> get failureStream => _failureController.stream;
  Stream<String> get mediaCompleteStream => _mediaCompleteController.stream;

  final Map<int, int> _retryCount = {};

  DownloadManager({required this.config, required this.cacheRepo});

  /// 初始化工作线程池并监听 Worker 事件（Web 平台跳过）。
  /// Initializes the worker pool and subscribes to worker events (skipped on web).
  Future<void> init() async {
    if (PlatformDetector.isWeb) return;

    final workerCount = PlatformDetector.isMobile
        ? config.mobileWorkerCount
        : config.desktopWorkerCount;

    _pool = DownloadWorkerPool(workerCount: workerCount, config: config);
    await _pool.start();

    _eventSub = _pool.events.listen(_onWorkerEvent);
    Logger.info('DownloadManager initialized with $workerCount workers');
  }

  void _onWorkerEvent(WorkerEvent event) {
    switch (event) {
      case ChunkProgress():
        _progressController.add(event);
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
      case WorkerCancelled():
        _dispatchNext();
        break;
    }
  }

  Future<void> _onChunkCompleted(ChunkCompleted event) async {
    _completionController.add(event);
    _retryCount.remove(event.chunkIndex);

    // Update bitmap
    if (_currentBitmap != null && _currentUrlHash != null) {
      _currentBitmap = _currentBitmap!.setChunkCompleted(event.chunkIndex, event.bytesWritten);
      await cacheRepo.updateBitmap(_currentBitmap!);

      // Check if all chunks complete
      if (_currentMedia != null) {
        final incomplete = _currentBitmap!.getIncompleteChunks(_currentMedia!.totalChunks);
        if (incomplete.isEmpty) {
          await cacheRepo.markCompleted(_currentUrlHash!);
          _mediaCompleteController.add(_currentUrlHash!);
          Logger.info('All chunks completed for $_currentUrlHash');

          // Trigger merge
          _mergeInBackground();
        }
      }
    }

    _dispatchNext();
  }

  void _onChunkFailed(ChunkFailed event) {
    _failureController.add(event);

    if (event.retryable) {
      final count = _retryCount[event.chunkIndex] ?? 0;
      if (count < config.maxRetryCount) {
        _retryCount[event.chunkIndex] = count + 1;
        final delayMs = config.retryBaseDelayMs * (1 << count);
        Logger.warning(
          'Chunk ${event.chunkIndex} failed, retry ${count + 1}/${config.maxRetryCount} in ${delayMs}ms',
        );
        Future.delayed(Duration(milliseconds: delayMs), () {
          _resubmitChunk(event.chunkIndex);
        });
        return;
      }
    }
    Logger.error('Chunk ${event.chunkIndex} permanently failed: ${event.errorMessage}');
    _dispatchNext();
  }

  void _resubmitChunk(int chunkIndex) {
    if (_currentMedia == null) return;
    final task = _createTask(chunkIndex, TaskPriority.p0Urgent);
    if (task != null) {
      _taskQueue.add(task);
      _dispatchNext();
    }
  }

  /// 开始下载指定媒体的所有未完成分片。
  /// Starts downloading all incomplete chunks for the specified media.
  Future<void> startDownload(String url, MediaIndex media) async {
    if (PlatformDetector.isWeb) return;

    _currentUrlHash = media.urlHash;
    _currentMedia = media;
    _currentBitmap = await cacheRepo.getBitmap(media.urlHash);
    _taskQueue.clear();
    _retryCount.clear();

    if (_currentBitmap == null) return;
    if (media.isCompleted) return;

    // Queue background fill
    final incomplete = _currentBitmap!.getIncompleteChunks(media.totalChunks);
    for (final idx in incomplete) {
      final task = _createTask(idx, TaskPriority.p3Low);
      if (task != null) _taskQueue.add(task);
    }

    _dispatchNext();
  }

  /// 处理 Seek 操作：重建任务队列，优先下载目标分片。
  /// Handles seek: rebuilds the task queue with the target chunk at highest priority.
  void onSeek(int byteOffset) {
    if (_currentMedia == null || _currentBitmap == null) return;

    final targetChunk = byteOffset ~/ config.chunkSize;

    // Cancel non-critical tasks
    _pool.cancelAll();

    // Rebuild queue with new priorities
    _taskQueue.clear();

    final incomplete = _currentBitmap!.getIncompleteChunks(_currentMedia!.totalChunks);

    for (final idx in incomplete) {
      TaskPriority priority;
      if (idx == targetChunk) {
        priority = TaskPriority.p0Urgent;
      } else if (idx > targetChunk && idx <= targetChunk + config.prefetchCount) {
        priority = TaskPriority.p1High;
      } else {
        priority = TaskPriority.p3Low;
      }
      final task = _createTask(idx, priority);
      if (task != null) _taskQueue.add(task);
    }

    _dispatchNext();
  }

  /// 将指定分片提升为最高优先级。
  /// Promotes the specified chunk to the highest priority.
  void requestChunkPriority(int chunkIndex) {
    if (_currentMedia == null || _currentBitmap == null) return;
    if (_currentBitmap!.isChunkCompleted(chunkIndex)) return;

    // Check if already being downloaded
    if (_pool.activeChunkIndices.contains(chunkIndex)) return;

    // Add as P0
    final task = _createTask(chunkIndex, TaskPriority.p0Urgent);
    if (task != null) {
      _taskQueue.add(task);
      _dispatchNext();
    }
  }

  DownloadTask? _createTask(int chunkIndex, TaskPriority priority) {
    if (_currentMedia == null) return null;
    final media = _currentMedia!;
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
    while (_pool.hasAvailableWorker && _taskQueue.isNotEmpty) {
      final task = _taskQueue.first;
      _taskQueue.remove(task);

      // Skip already completed
      if (_currentBitmap != null && _currentBitmap!.isChunkCompleted(task.chunkIndex)) {
        continue;
      }
      // Skip already in progress
      if (_pool.activeChunkIndices.contains(task.chunkIndex)) {
        continue;
      }

      _pool.submitTask(task);
    }
  }

  Future<void> _mergeInBackground() async {
    if (_currentMedia == null) return;
    try {
      await ChunkMerger.mergeChunks(
        mediaDir: _currentMedia!.localDir,
        totalChunks: _currentMedia!.totalChunks,
      );
    } catch (e) {
      Logger.error('Chunk merge failed', e);
    }
  }

  /// 取消所有下载并清空队列。
  /// Cancels all active downloads and clears the task queue.
  void cancelAll() {
    _pool.cancelAll();
    _taskQueue.clear();
  }

  /// 检查指定分片是否已下载完成。
  /// Checks whether the specified chunk has been downloaded.
  bool isChunkReady(int chunkIndex) {
    return _currentBitmap?.isChunkCompleted(chunkIndex) ?? false;
  }

  ChunkBitmap? get currentBitmap => _currentBitmap;

  /// 释放资源，关闭工作池和所有事件流。
  /// Disposes resources, shutting down the pool and all event streams.
  Future<void> dispose() async {
    cancelAll();
    await _eventSub?.cancel();
    await _pool.shutdown();
    await _progressController.close();
    await _completionController.close();
    await _failureController.close();
    await _mediaCompleteController.close();
  }
}
