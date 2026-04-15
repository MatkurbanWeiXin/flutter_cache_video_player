import 'dart:async';
import 'dart:isolate';
import 'package:signals_flutter/signals_flutter.dart';
import '../core/constants.dart';
import '../core/logger.dart';
import 'download_task.dart';
import 'download_worker.dart';

/// 单个 Worker 的内部句柄，维护 Isolate 及其状态。
/// Internal handle for a single worker, maintaining its Isolate and state.
class _WorkerHandle {
  final Isolate isolate;
  final SendPort sendPort;
  bool isBusy = false;
  int? currentChunkIndex;

  _WorkerHandle({required this.isolate, required this.sendPort});
}

/// Isolate 工作线程池，管理 N 个长驻工作 Isolate。
/// Isolate worker pool managing N long-lived worker Isolates.
class DownloadWorkerPool {
  final int workerCount;
  final CacheConfig config;
  final List<_WorkerHandle> _workers = [];
  final latestEvent = signal<WorkerEvent?>(null);
  bool _isReady = false;

  DownloadWorkerPool({required this.workerCount, required this.config});
  bool get isReady => _isReady;

  /// 启动所有 Worker Isolate。
  /// Starts all Worker Isolates.
  Future<void> start() async {
    for (int i = 0; i < workerCount; i++) {
      final handle = await _spawnWorker(i);
      _workers.add(handle);
    }
    _isReady = true;
    Logger.info('Worker pool started with $workerCount workers');
  }

  Future<_WorkerHandle> _spawnWorker(int index) async {
    final receivePort = ReceivePort();
    final completer = Completer<SendPort>();

    final isolate = await Isolate.spawn(
      DownloadWorkerEntry.workerMain,
      receivePort.sendPort,
      debugName: 'DownloadWorker-$index',
      errorsAreFatal: false,
    );

    isolate.addErrorListener(receivePort.sendPort);

    receivePort.listen((dynamic message) {
      if (message is SendPort) {
        completer.complete(message);
      } else if (message is Map<String, dynamic>) {
        final event = message['event'] as String?;
        if (event == 'ready') {
          Logger.debug('Worker-$index ready');
        } else if (event != null) {
          _handleWorkerEvent(index, WorkerEvent.fromMessage(message));
        }
      } else if (message is List && message.length == 2) {
        // Error from isolate
        Logger.error('Worker-$index error: ${message[0]}');
        _respawnWorker(index);
      }
    });

    final sendPort = await completer.future;
    return _WorkerHandle(isolate: isolate, sendPort: sendPort);
  }

  void _handleWorkerEvent(int workerIndex, WorkerEvent event) {
    if (workerIndex < _workers.length) {
      if (event is ChunkCompleted || event is ChunkFailed || event is WorkerCancelled) {
        final handle = _workers[workerIndex];
        // 仅在事件 chunkIndex 与当前任务匹配时重置状态。
        // cancelAll() 已立即重置过——忽略后续到达的过期事件，
        // 避免误释放正在执行新任务的 Worker。
        // Only reset state when the event's chunkIndex matches the current task.
        // cancelAll() already reset state eagerly — stale events arriving later
        // must not accidentally free a worker that is now handling a new task.
        final eventChunk = switch (event) {
          ChunkCompleted e => e.chunkIndex,
          ChunkFailed e => e.chunkIndex,
          WorkerCancelled e => e.chunkIndex,
          _ => null,
        };
        if (handle.currentChunkIndex == eventChunk) {
          handle.isBusy = false;
          handle.currentChunkIndex = null;
        }
      }
    }
    // ChunkProgress 事件量极大（每个网络缓冲区一次），传播到信号链会
    // 引发信号洪泛。仅转发完成/失败/取消/就绪等低频事件。
    // ChunkProgress events are extremely frequent (one per network buffer).
    // Only propagate low-frequency lifecycle events to the signal chain.
    if (event is! ChunkProgress) {
      latestEvent.set(event, force: true);
    }
  }

  Future<void> _respawnWorker(int index) async {
    Logger.warning('Respawning Worker-$index');
    try {
      _workers[index].isolate.kill(priority: Isolate.immediate);
    } catch (_) {}
    final handle = await _spawnWorker(index);
    _workers[index] = handle;
  }

  /// 提交下载任务到空闲的 Worker，成功返回 true。
  /// Submits a download task to an available worker; returns true on success.
  bool submitTask(DownloadTask task) {
    final worker = _findAvailableWorker();
    if (worker == null) return false;

    worker.isBusy = true;
    worker.currentChunkIndex = task.chunkIndex;
    final msg = task.toMessage();
    msg['command'] = 'download';
    worker.sendPort.send(msg);
    return true;
  }

  _WorkerHandle? _findAvailableWorker() {
    for (final w in _workers) {
      if (!w.isBusy) return w;
    }
    return null;
  }

  bool get hasAvailableWorker => _workers.any((w) => !w.isBusy);

  /// 取消指定分片的下载（不立即释放 Worker，等待 cancelled 事件）。
  /// Cancels the download of the specified chunk (worker released upon cancelled event).
  void cancelChunk(int chunkIndex) {
    for (final w in _workers) {
      if (w.currentChunkIndex == chunkIndex) {
        w.sendPort.send({'command': 'cancel'});
        break;
      }
    }
  }

  /// 取消所有正在进行的下载并立即释放 Worker。
  /// Cancels all in-progress downloads and immediately marks workers as available.
  void cancelAll() {
    for (final w in _workers) {
      if (w.isBusy) {
        w.sendPort.send({'command': 'cancel'});
        w.isBusy = false;
        w.currentChunkIndex = null;
      }
    }
  }

  Set<int> get activeChunkIndices {
    return _workers
        .where((w) => w.isBusy && w.currentChunkIndex != null)
        .map((w) => w.currentChunkIndex!)
        .toSet();
  }

  /// 关闭所有 Worker 并释放资源。
  /// Shuts down all workers and releases resources.
  Future<void> shutdown() async {
    for (final w in _workers) {
      w.sendPort.send({'command': 'shutdown'});
    }
    _workers.clear();
    _isReady = false;
    Logger.info('Worker pool shut down');
  }
}
