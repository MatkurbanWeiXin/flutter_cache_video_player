/// 任务优先级枚举，P0 最高，P3 最低。
/// Task priority enumeration: P0 is highest, P3 is lowest.
enum TaskPriority { p0Urgent, p1High, p2Medium, p3Low }

/// 分片下载任务数据类，包含下载所需的所有信息。
/// Chunk download task data class holding all information needed for a download.
class DownloadTask {
  final String url;
  final String urlHash;
  final int chunkIndex;
  final int byteStart;
  final int byteEnd;
  final String savePath;
  final TaskPriority priority;

  const DownloadTask({
    required this.url,
    required this.urlHash,
    required this.chunkIndex,
    required this.byteStart,
    required this.byteEnd,
    required this.savePath,
    this.priority = TaskPriority.p3Low,
  });

  /// 序列化为 Isolate 消息。
  /// Serializes to an Isolate message map.
  Map<String, dynamic> toMessage() => {
    'url': url,
    'url_hash': urlHash,
    'chunk_index': chunkIndex,
    'byte_start': byteStart,
    'byte_end': byteEnd,
    'save_path': savePath,
  };

  /// 从 Isolate 消息反序列化。
  /// Deserializes from an Isolate message map.
  factory DownloadTask.fromMessage(Map<String, dynamic> msg) => DownloadTask(
    url: msg['url'] as String,
    urlHash: msg['url_hash'] as String,
    chunkIndex: msg['chunk_index'] as int,
    byteStart: msg['byte_start'] as int,
    byteEnd: msg['byte_end'] as int,
    savePath: msg['save_path'] as String,
  );
}

/// Worker 命令密封类，由主 Isolate 发送给工作 Isolate。
/// Sealed class for commands sent from the main Isolate to worker Isolates.
sealed class WorkerCommand {
  Map<String, dynamic> toMessage();
}

/// 下载分片命令。
/// Command to download a chunk.
class DownloadChunkCommand extends WorkerCommand {
  final DownloadTask task;
  DownloadChunkCommand(this.task);

  @override
  Map<String, dynamic> toMessage() => {'command': 'download', ...task.toMessage()};
}

/// 取消当前下载命令。
/// Command to cancel the current download.
class CancelCurrentCommand extends WorkerCommand {
  @override
  Map<String, dynamic> toMessage() => {'command': 'cancel'};
}

/// 关闭工作 Isolate 命令。
/// Command to shut down the worker Isolate.
class ShutdownCommand extends WorkerCommand {
  @override
  Map<String, dynamic> toMessage() => {'command': 'shutdown'};
}

/// Worker 事件密封类，由工作 Isolate 发送给主 Isolate。
/// Sealed class for events sent from worker Isolates to the main Isolate.
sealed class WorkerEvent {
  const WorkerEvent();

  /// 从消息 Map 解析为具体事件类型。
  /// Parses a message map into a concrete event type.
  factory WorkerEvent.fromMessage(Map<String, dynamic> msg) {
    switch (msg['event'] as String) {
      case 'progress':
        return ChunkProgress(
          chunkIndex: msg['chunk_index'] as int,
          downloadedBytes: msg['downloaded_bytes'] as int,
          totalBytes: msg['total_bytes'] as int,
          data: msg['data'] as List<int>?,
        );
      case 'completed':
        return ChunkCompleted(
          chunkIndex: msg['chunk_index'] as int,
          filePath: msg['file_path'] as String,
          bytesWritten: msg['bytes_written'] as int,
        );
      case 'failed':
        return ChunkFailed(
          chunkIndex: msg['chunk_index'] as int,
          errorMessage: msg['error_message'] as String,
          retryable: msg['retryable'] as bool,
        );
      case 'cancelled':
        return WorkerCancelled(chunkIndex: msg['chunk_index'] as int);
      case 'ready':
        return WorkerReady();
      default:
        throw ArgumentError('Unknown worker event: ${msg['event']}');
    }
  }
}

/// 分片下载进度事件，包含已下载字节和流数据。
/// Chunk download progress event carrying downloaded bytes and stream data.
class ChunkProgress extends WorkerEvent {
  final int chunkIndex;
  final int downloadedBytes;
  final int totalBytes;
  final List<int>? data;

  const ChunkProgress({
    required this.chunkIndex,
    required this.downloadedBytes,
    required this.totalBytes,
    this.data,
  });

  Map<String, dynamic> toMessage() => {
    'event': 'progress',
    'chunk_index': chunkIndex,
    'downloaded_bytes': downloadedBytes,
    'total_bytes': totalBytes,
    'data': data,
  };
}

/// 分片下载完成事件。
/// Chunk download completion event.
class ChunkCompleted extends WorkerEvent {
  final int chunkIndex;
  final String filePath;
  final int bytesWritten;

  const ChunkCompleted({
    required this.chunkIndex,
    required this.filePath,
    required this.bytesWritten,
  });

  Map<String, dynamic> toMessage() => {
    'event': 'completed',
    'chunk_index': chunkIndex,
    'file_path': filePath,
    'bytes_written': bytesWritten,
  };
}

/// 分片下载失败事件，包含错误信息和是否可重试。
/// Chunk download failure event carrying error details and retryability.
class ChunkFailed extends WorkerEvent {
  final int chunkIndex;
  final String errorMessage;
  final bool retryable;

  const ChunkFailed({required this.chunkIndex, required this.errorMessage, this.retryable = true});

  Map<String, dynamic> toMessage() => {
    'event': 'failed',
    'chunk_index': chunkIndex,
    'error_message': errorMessage,
    'retryable': retryable,
  };
}

/// Worker 就绪事件，表示工作 Isolate 已初始化完成。
/// Worker-ready event indicating the worker Isolate has finished initialization.
class WorkerReady extends WorkerEvent {
  const WorkerReady();
  Map<String, dynamic> toMessage() => {'event': 'ready'};
}

/// Worker 取消完成事件，表示取消操作已清理完毕。
/// Worker-cancelled event indicating the cancellation cleanup is done.
class WorkerCancelled extends WorkerEvent {
  final int chunkIndex;
  const WorkerCancelled({required this.chunkIndex});
  Map<String, dynamic> toMessage() => {'event': 'cancelled', 'chunk_index': chunkIndex};
}
