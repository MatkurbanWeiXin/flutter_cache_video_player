import 'package:flutter/foundation.dart';
import '../core/logger.dart';
import '../proxy/proxy_server.dart';

/// 平台播放工厂，根据平台返回代理 URL 或原始 URL。
/// Platform player factory returning a proxy URL on native or the original URL on web.
class PlatformPlayerFactory {
  final ProxyCacheServer? proxyServer;

  PlatformPlayerFactory({this.proxyServer});

  /// 创建播放器所用的媒体 URL。
  /// 原生端（含 Windows）：已完全缓存时使用 file:// URL，否则走本地 HTTP 代理。
  /// Web 端：使用原始 URL。
  ///
  /// Creates the media URL for the player.
  /// Native (including Windows): uses file:// for fully cached media, otherwise local HTTP proxy.
  /// Web: uses original URL.
  Future<String> createMediaUrl(String originalUrl) async {
    if (kIsWeb || proxyServer == null) {
      return originalUrl;
    }

    // 所有原生平台：优先检查是否已完全缓存，命中则直接 file:// 播放。
    // All native platforms: check for fully cached file first, play via file:// if available.
    final cachedUrl = await proxyServer!.getCachedFileUrl(originalUrl);
    if (cachedUrl != null) {
      Logger.info('Playing from cache: $cachedUrl');
      return cachedUrl;
    }

    return proxyServer!.proxyUrl(originalUrl);
  }
}
