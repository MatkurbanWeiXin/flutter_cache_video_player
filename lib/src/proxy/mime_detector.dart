/// MIME 类型检测器，根据文件扩展名推断媒体类型。
/// MIME type detector that infers media type from file extension.
class MimeDetector {
  static const _extensionMap = {
    '.mp4': 'video/mp4',
    '.m4v': 'video/mp4',
    '.mkv': 'video/x-matroska',
    '.webm': 'video/webm',
    '.avi': 'video/x-msvideo',
    '.mov': 'video/quicktime',
    '.flv': 'video/x-flv',
    '.wmv': 'video/x-ms-wmv',
    '.ts': 'video/mp2t',
    '.mp3': 'audio/mpeg',
    '.m4a': 'audio/mp4',
    '.aac': 'audio/aac',
    '.ogg': 'audio/ogg',
    '.opus': 'audio/opus',
    '.wav': 'audio/wav',
    '.flac': 'audio/flac',
    '.wma': 'audio/x-ms-wma',
  };

  /// 根据 URL 检测 MIME 类型。
  /// Detects MIME type from the given URL.
  static String detect(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'application/octet-stream';

    final path = uri.path.toLowerCase();
    for (final entry in _extensionMap.entries) {
      if (path.endsWith(entry.key)) return entry.value;
    }
    return 'application/octet-stream';
  }

  /// 判断是否为视频 MIME 类型。
  /// Checks whether the MIME type is a video type.
  static bool isVideo(String mimeType) => mimeType.startsWith('video/');

  /// 判断是否为音频 MIME 类型。
  /// Checks whether the MIME type is an audio type.
  static bool isAudio(String mimeType) => mimeType.startsWith('audio/');
}
