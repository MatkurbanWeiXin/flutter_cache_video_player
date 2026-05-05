// Core
export 'src/core/constants.dart';
export 'src/core/platform_detector.dart';
export 'src/core/video_source.dart';

// Data models
export 'src/data/models/media_index.dart';
export 'src/data/models/chunk_bitmap.dart';
export 'src/data/models/playback_history.dart';
export 'src/data/models/video_cover_frame.dart';
export 'src/data/enums/play_state.dart';

// Data repositories
export 'src/data/cache_index_db.dart';
export 'src/data/repositories/cache_repository.dart';
export 'src/data/repositories/history_repository.dart';

// Download
export 'src/download/download_task.dart';
export 'src/download/download_manager.dart';
export 'src/download/download_worker_pool.dart';
export 'src/download/chunk_merger.dart';

// Proxy
export 'src/proxy/proxy_server.dart';
export 'src/proxy/range_handler.dart';
export 'src/proxy/mime_detector.dart';

// Player
export 'src/player/video_player_controller.dart';
export 'src/player/platform_player_factory.dart';

// UI
export 'src/ui/core_player.dart';
export 'src/ui/video_player.dart';
export 'src/ui/style/video_player_theme.dart';
export 'src/ui/widgets/player_scrubber_slider.dart';

// Utils
export 'src/utils/url_hasher.dart';
export 'src/utils/file_utils.dart';
export 'src/utils/size_formatter.dart';

// App
export 'src/cache_video_player.dart';

// Re-export XFile so consumers can use it without adding cross_file explicitly.
export 'package:cross_file/cross_file.dart' show XFile;
