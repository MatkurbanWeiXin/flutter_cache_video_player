/// 缓存配置类，包含所有可调参数。
/// Cache configuration class containing all tunable parameters.
class CacheConfig {
  /// 单个分片大小（字节），默认 2MB。
  /// Size of a single chunk in bytes. Default: 2MB.
  final int chunkSize;

  /// 最大缓存容量（字节），默认 2GB。
  /// Maximum cache capacity in bytes. Default: 2GB.
  final int maxCacheBytes;

  /// 移动端 Worker Isolate 并发数。
  /// Number of worker isolates on mobile platforms.
  final int mobileWorkerCount;

  /// 桌面端 Worker Isolate 并发数。
  /// Number of worker isolates on desktop platforms.
  final int desktopWorkerCount;

  /// 播放时向前预取的分片数量。
  /// Number of chunks to prefetch ahead during playback.
  final int prefetchCount;

  /// 下载失败最大重试次数。
  /// Maximum number of retries for failed downloads.
  final int maxRetryCount;

  /// 重试退避基础延迟（毫秒）。
  /// Base delay in milliseconds for exponential backoff retry.
  final int retryBaseDelayMs;

  /// Worker → 主 Isolate 消息分片大小（字节）。
  /// Message chunk size for worker-to-main isolate communication.
  final int messageChunkSize;

  /// 流分发器背压上限（字节）。
  /// High water mark for StreamSplitter back-pressure in bytes.
  final int highWaterMark;

  /// 是否仅在 Wi-Fi 下下载（移动端默认 true）。
  /// Whether to download only on Wi-Fi (default true on mobile).
  final bool wifiOnlyDownload;

  /// 是否启用播放列表预加载。
  /// Whether to enable playlist prefetch.
  final bool enablePlaylistPrefetch;

  /// 分片完成后是否校验 MD5。
  /// Whether to verify MD5 checksum after chunk download.
  final bool enableChunkChecksum;

  /// 低速网络阈值（bytes/s）。
  /// Low speed threshold in bytes per second.
  final int lowSpeedThreshold;

  /// 高速网络阈值（bytes/s）。
  /// High speed threshold in bytes per second.
  final int highSpeedThreshold;

  const CacheConfig({
    this.chunkSize = 2 * 1024 * 1024,
    this.maxCacheBytes = 2 * 1024 * 1024 * 1024,
    this.mobileWorkerCount = 2,
    this.desktopWorkerCount = 4,
    this.prefetchCount = 3,
    this.maxRetryCount = 3,
    this.retryBaseDelayMs = 1000,
    this.messageChunkSize = 64 * 1024,
    this.highWaterMark = 256 * 1024,
    this.wifiOnlyDownload = true,
    this.enablePlaylistPrefetch = true,
    this.enableChunkChecksum = false,
    this.lowSpeedThreshold = 128 * 1024,
    this.highSpeedThreshold = 1280 * 1024,
  });

  /// 创建当前配置的副本，可选择性覆盖部分参数。
  /// Creates a copy of this config with optionally overridden fields.
  CacheConfig copyWith({
    int? chunkSize,
    int? maxCacheBytes,
    int? mobileWorkerCount,
    int? desktopWorkerCount,
    int? prefetchCount,
    int? maxRetryCount,
    int? retryBaseDelayMs,
    int? messageChunkSize,
    int? highWaterMark,
    bool? wifiOnlyDownload,
    bool? enablePlaylistPrefetch,
    bool? enableChunkChecksum,
    int? lowSpeedThreshold,
    int? highSpeedThreshold,
  }) {
    return CacheConfig(
      chunkSize: chunkSize ?? this.chunkSize,
      maxCacheBytes: maxCacheBytes ?? this.maxCacheBytes,
      mobileWorkerCount: mobileWorkerCount ?? this.mobileWorkerCount,
      desktopWorkerCount: desktopWorkerCount ?? this.desktopWorkerCount,
      prefetchCount: prefetchCount ?? this.prefetchCount,
      maxRetryCount: maxRetryCount ?? this.maxRetryCount,
      retryBaseDelayMs: retryBaseDelayMs ?? this.retryBaseDelayMs,
      messageChunkSize: messageChunkSize ?? this.messageChunkSize,
      highWaterMark: highWaterMark ?? this.highWaterMark,
      wifiOnlyDownload: wifiOnlyDownload ?? this.wifiOnlyDownload,
      enablePlaylistPrefetch: enablePlaylistPrefetch ?? this.enablePlaylistPrefetch,
      enableChunkChecksum: enableChunkChecksum ?? this.enableChunkChecksum,
      lowSpeedThreshold: lowSpeedThreshold ?? this.lowSpeedThreshold,
      highSpeedThreshold: highSpeedThreshold ?? this.highSpeedThreshold,
    );
  }
}
