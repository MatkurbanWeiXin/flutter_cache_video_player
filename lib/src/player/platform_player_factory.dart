import 'package:flutter/foundation.dart';

import '../core/video_source.dart';
import '../proxy/proxy_server.dart';

/// 平台播放工厂，根据来源决定是否走本地缓存代理。
///
/// Platform player factory. Decides whether a given [VideoSource] should be
/// routed through the local HTTP cache proxy (network only, native only) or
/// consumed directly by the native player (file / asset / web).
class PlatformPlayerFactory {
  final ProxyCacheServer? proxyServer;

  PlatformPlayerFactory({this.proxyServer});

  /// 为指定来源构造原生播放器可消费的 URL。
  ///
  /// * [NetworkVideoSource] 且非 Web：预热 `initCache`，再返回代理 URL；失败时回退直连。
  /// * 其它来源：直接返回 [resolvedNativeUrl]。
  ///
  /// Build the URL the native player will actually open. Network sources on
  /// native platforms are piped through the caching proxy; all other sources
  /// are handed the native URL as-is.
  Future<String> createMediaUrl(VideoSource source, String resolvedNativeUrl) async {
    if (source is! NetworkVideoSource) {
      return resolvedNativeUrl;
    }
    if (kIsWeb || proxyServer == null) {
      return resolvedNativeUrl;
    }

    try {
      await proxyServer!.initCache(resolvedNativeUrl);
    } catch (_) {
      return resolvedNativeUrl;
    }
    return proxyServer!.proxyUrl(resolvedNativeUrl);
  }
}
