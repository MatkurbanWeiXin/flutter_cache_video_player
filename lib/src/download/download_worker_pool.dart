import 'dart:async';
import 'dart:isolate';
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
  final _eventController = StreamController<WorkerEvent>.broadcast();
  bool _isReady = false;

  DownloadWorkerPool({required this.workerCount, required this.config});

  Stream<WorkerEvent> get events => _eventController.stream;
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
        _workers[workerIndex].isBusy = false;
        _workers[workerIndex].currentChunkIndex = null;
      }
    }
    _eventController.add(event);
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

  /// 取消所有正在进行的下载（不立即释放 Worker，等待 cancelled 事件）。
  /// Cancels all in-progress downloads (workers released upon cancelled events).
  void cancelAll() {
    for (final w in _workers) {
      if (w.isBusy) {
        w.sendPort.send({'command': 'cancel'});
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
    await _eventController.close();
    Logger.info('Worker pool shut down');
  }
}
