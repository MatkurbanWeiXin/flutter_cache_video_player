import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:dio/dio.dart';

/// Isolate 工作入口，负责在独立 Isolate 中执行分片下载。
/// Isolate worker entry point responsible for executing chunk downloads in a separate Isolate.
class DownloadWorkerEntry {
  /// Isolate 入口函数，接收主 Isolate 的 SendPort 并监听命令。
  /// Isolate entry function that receives the main Isolate’s SendPort and listens for commands.
  static void workerMain(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 5,
      ),
    );

    CancelToken? currentCancelToken;

    receivePort.listen((dynamic message) async {
      if (message is! Map<String, dynamic>) return;
      final command = message['command'] as String;

      switch (command) {
        case 'download':
          currentCancelToken = CancelToken();
          await _handleDownload(dio, message, mainSendPort, currentCancelToken!);
          break;
        case 'cancel':
          currentCancelToken?.cancel('Cancelled by user');
          currentCancelToken = null;
          break;
        case 'shutdown':
          dio.close();
          receivePort.close();
          Isolate.exit();
      }
    });

    mainSendPort.send({'event': 'ready'});
  }

  static Future<void> _handleDownload(
    Dio dio,
    Map<String, dynamic> task,
    SendPort sendPort,
    CancelToken cancelToken,
  ) async {
    final url = task['url'] as String;
    final chunkIndex = task['chunk_index'] as int;
    final byteStart = task['byte_start'] as int;
    final byteEnd = task['byte_end'] as int;
    final savePath = task['save_path'] as String;

    final tmpPath = '$savePath.tmp';
    RandomAccessFile? raf;

    try {
      // Ensure parent directory exists (may have been deleted by LRU eviction)
      final parentDir = File(savePath).parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      raf = await File(tmpPath).open(mode: FileMode.write);
      int totalDownloaded = 0;
      final expectedBytes = byteEnd - byteStart + 1;

      final response = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=$byteStart-$byteEnd'},
        ),
        cancelToken: cancelToken,
      );

      final stream = response.data!.stream;

      // 节流进度事件：最多每 200ms 发送一次，避免信号洪泛。
      // Throttle progress events to at most once per 200ms to prevent signal flooding.
      var lastProgressTime = DateTime.now().millisecondsSinceEpoch;
      const progressIntervalMs = 200;

      await for (final chunk in stream) {
        if (cancelToken.isCancelled) break;

        await raf.writeFrom(chunk);
        totalDownloaded += chunk.length;

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastProgressTime >= progressIntervalMs) {
          lastProgressTime = now;
          sendPort.send({
            'event': 'progress',
            'chunk_index': chunkIndex,
            'downloaded_bytes': totalDownloaded,
            'total_bytes': expectedBytes,
          });
        }
      }

      await raf.close();
      raf = null;

      if (!cancelToken.isCancelled) {
        // Atomic rename
        await File(tmpPath).rename(savePath);
        sendPort.send({
          'event': 'completed',
          'chunk_index': chunkIndex,
          'file_path': savePath,
          'bytes_written': totalDownloaded,
        });
      } else {
        await _cleanupTmp(tmpPath);
        sendPort.send({'event': 'cancelled', 'chunk_index': chunkIndex});
      }
    } on DioException catch (e) {
      await raf?.close();
      await _cleanupTmp(tmpPath);

      if (e.type == DioExceptionType.cancel) {
        sendPort.send({'event': 'cancelled', 'chunk_index': chunkIndex});
        return;
      }

      final retryable =
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError;

      sendPort.send({
        'event': 'failed',
        'chunk_index': chunkIndex,
        'error_message': e.message ?? e.toString(),
        'retryable': retryable,
      });
    } catch (e) {
      await raf?.close();
      await _cleanupTmp(tmpPath);

      sendPort.send({
        'event': 'failed',
        'chunk_index': chunkIndex,
        'error_message': e.toString(),
        'retryable': false,
      });
    }
  }

  static Future<void> _cleanupTmp(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
