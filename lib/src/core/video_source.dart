import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/asset_extractor.dart';

/// 描述一个视频 / 音频的来源。
///
/// * [NetworkVideoSource] ─ 网络地址（`http(s)://...`），走插件的缓存代理。
/// * [FileVideoSource]    ─ 本地绝对路径或 `file://` URI，不走代理。
/// * [AssetVideoSource]   ─ Flutter assets，由插件自动抽取到临时目录后以 `file://` 交给原生播放器。
///
/// A sealed description of a playable media source.
///
/// * [NetworkVideoSource] – HTTP(S) URL, routed through the caching proxy.
/// * [FileVideoSource]    – Local absolute path or `file://` URI, bypasses the proxy.
/// * [AssetVideoSource]   – Flutter asset; the plugin extracts it to the temp
///   directory and hands the `file://` URI to the native player.
@immutable
sealed class VideoSource {
  const VideoSource();

  /// 用作历史记录、mime 探测的稳定标识。
  /// Stable identity used for history keys and mime sniffing.
  String get identity;

  /// 是否可走 HTTP 缓存代理。只有 [NetworkVideoSource] 为 true。
  /// Whether this source is eligible for the HTTP caching proxy.
  bool get isNetwork => false;

  /// 将来源解析为原生播放器可直接消费的 URL。
  ///
  /// * 网络：原样返回（代理逻辑由工厂再决定）
  /// * 文件：规范化为 `file:///absolute/path`
  /// * 资源：懒抽取到缓存目录并返回 `file://` URI
  ///
  /// Resolve this source into a URL the native player can consume directly.
  Future<String> resolveToNativeUrl();

  /// 快速构造一个网络来源。
  /// Shortcut for a network URL.
  const factory VideoSource.network(String url) = NetworkVideoSource;

  /// 快速构造一个本地文件来源。
  /// Shortcut for a local file path / URI.
  const factory VideoSource.file(String path) = FileVideoSource;

  /// 快速构造一个资源来源。
  /// Shortcut for a Flutter asset.
  const factory VideoSource.asset(String assetPath, {AssetBundle? bundle}) = AssetVideoSource;
}

/// 网络来源，走 HTTP 缓存代理。
/// Network-backed media source, eligible for the HTTP caching proxy.
class NetworkVideoSource extends VideoSource {
  /// 原始网络地址。
  /// Original network URL.
  final String url;

  const NetworkVideoSource(this.url);

  @override
  String get identity => url;

  @override
  bool get isNetwork => true;

  @override
  Future<String> resolveToNativeUrl() async => url;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NetworkVideoSource && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// 本地文件来源（绝对路径或 `file://` URI），不走代理。
/// Local file media source (absolute path or `file://` URI). Bypasses the proxy.
class FileVideoSource extends VideoSource {
  /// 文件路径或 `file://` URI。
  /// Raw path or `file://` URI.
  final String path;

  const FileVideoSource(this.path);

  @override
  String get identity {
    final normalized = path.startsWith('file://') ? path : 'file://$path';
    return normalized;
  }

  @override
  Future<String> resolveToNativeUrl() async {
    if (path.startsWith('file://')) return path;
    return Uri.file(path).toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is FileVideoSource && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// Flutter assets 来源；首次使用时自动抽取到临时目录并缓存。
/// Flutter asset media source; extracted to the temp directory on first use.
class AssetVideoSource extends VideoSource {
  /// Asset 路径（与 `rootBundle.load(...)` 相同）。
  /// Asset key (same as `rootBundle.load(...)`).
  final String assetPath;

  /// 自定义 asset bundle，默认 `rootBundle`。
  /// Custom asset bundle, defaults to [rootBundle].
  final AssetBundle? bundle;

  const AssetVideoSource(this.assetPath, {this.bundle});

  @override
  String get identity => 'asset://$assetPath';

  @override
  Future<String> resolveToNativeUrl() async {
    final path = await AssetExtractor.extract(assetPath, bundle: bundle);
    return Uri.file(path).toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetVideoSource && other.assetPath == assetPath && identical(other.bundle, bundle);

  @override
  int get hashCode => Object.hash(assetPath, bundle);
}
