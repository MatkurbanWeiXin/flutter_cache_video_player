import 'package:flutter/foundation.dart';
import '../proxy/proxy_server.dart';

/// 平台播放工厂，根据平台返回代理 URL 或原始 URL。
/// Platform player factory returning a proxy URL on native or the original URL on web.
class PlatformPlayerFactory {
  final ProxyCacheServer? proxyServer;

  PlatformPlayerFactory({this.proxyServer});

  /// 创建播放器所用的媒体 URL：原生端走代理，Web 端用原始 URL。
  /// Creates the media URL for the player: proxy on native, original URL on web.
  String createMediaUrl(String originalUrl) {
    if (kIsWeb || proxyServer == null) {
      return originalUrl;
    }
    return proxyServer!.proxyUrl(originalUrl);
  }
}
