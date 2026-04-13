import 'package:signals/signals.dart';
import '../core/constants.dart';
import '../core/logger.dart';
import 'flutter_cache_video_player_controller.dart';

/// 播放列表项数据类。
/// Playlist item data class.
class PlaylistItem {
  final String url;
  final String title;
  final String? coverUrl;

  const PlaylistItem({required this.url, required this.title, this.coverUrl});
}

/// 播放列表控制器，支持顺序/随机/循环模式。
/// Playlist controller supporting sequential, shuffle, and repeat modes.
class FlutterCacheVideoPlaylistController {
  final FlutterCacheVideoPlayerController controller;
  final CacheConfig config;

  final List<PlaylistItem> _items = [];
  final currentIndex = signal(-1);
  bool _shuffle = false;
  bool _repeat = false;

  FlutterCacheVideoPlaylistController({required this.controller, required this.config});

  List<PlaylistItem> get items => List.unmodifiable(_items);
  PlaylistItem? get currentItem {
    final idx = currentIndex.value;
    return idx >= 0 && idx < _items.length ? _items[idx] : null;
  }

  bool get shuffle => _shuffle;
  bool get repeat => _repeat;

  /// 设置播放列表并指定起始索引。
  /// Sets the playlist and specifies the starting index.
  void setPlaylist(List<PlaylistItem> items, {int startIndex = 0}) {
    _items.clear();
    _items.addAll(items);
    currentIndex.value = startIndex;
    Logger.info('Playlist set: ${items.length} items, starting at $startIndex');
  }

  /// 播放指定索引的项目。
  /// Plays the item at the specified index.
  Future<void> playIndex(int index) async {
    if (index < 0 || index >= _items.length) return;
    currentIndex.value = index;
    await controller.open(_items[index].url, resumeHistory: false);
  }

  /// 播放下一曲，支持随机和循环模式。
  /// Plays the next item with shuffle and repeat support.
  Future<void> next() async {
    if (_items.isEmpty) return;
    int nextIndex;
    if (_shuffle) {
      nextIndex = (DateTime.now().microsecond % _items.length);
    } else {
      nextIndex = currentIndex.value + 1;
      if (nextIndex >= _items.length) {
        if (_repeat) {
          nextIndex = 0;
        } else {
          return;
        }
      }
    }
    await playIndex(nextIndex);
  }

  /// 播放上一曲，支持循环模式。
  /// Plays the previous item with repeat support.
  Future<void> previous() async {
    if (_items.isEmpty) return;
    int prevIndex = currentIndex.value - 1;
    if (prevIndex < 0) {
      if (_repeat) {
        prevIndex = _items.length - 1;
      } else {
        return;
      }
    }
    await playIndex(prevIndex);
  }

  /// 切换随机播放模式。
  /// Toggles shuffle mode.
  void toggleShuffle() => _shuffle = !_shuffle;

  /// 切换循环播放模式。
  /// Toggles repeat mode.
  void toggleRepeat() => _repeat = !_repeat;

  /// 添加一项到播放列表末尾。
  /// Appends an item to the end of the playlist.
  void addItem(PlaylistItem item) => _items.add(item);

  /// 移除指定索引的播放列表项。
  /// Removes the playlist item at the specified index.
  void removeAt(int index) {
    if (index < 0 || index >= _items.length) return;
    _items.removeAt(index);
    if (currentIndex.value >= _items.length) {
      currentIndex.value = _items.length - 1;
    }
  }

  /// 释放资源。
  /// Disposes resources.
  void dispose() {}
}
