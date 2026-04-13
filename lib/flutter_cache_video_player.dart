// Core
export 'src/core/constants.dart';
export 'src/core/platform_detector.dart';
export 'src/core/logger.dart';

// Data models
export 'src/data/models/media_index.dart';
export 'src/data/models/chunk_bitmap.dart';
export 'src/data/models/playback_history.dart';

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
export 'src/proxy/stream_splitter.dart';

// Player
export 'src/player/player_service.dart';
export 'src/player/player_state.dart';
export 'src/player/platform_player_factory.dart';
export 'src/player/playlist_manager.dart';

// UI - Themes
export 'src/ui/themes/light_theme.dart';
export 'src/ui/themes/dark_theme.dart';
export 'src/ui/themes/theme_controller.dart';

// UI - Layouts
export 'src/ui/layouts/mobile_layout.dart';
export 'src/ui/layouts/tablet_layout.dart';
export 'src/ui/layouts/desktop_layout.dart';
export 'src/ui/responsive/adaptive_scaffold.dart';

// UI - Widgets
export 'src/ui/widgets/video_player_widget.dart';
export 'src/ui/widgets/audio_player_widget.dart';
export 'src/ui/widgets/progress_bar.dart';
export 'src/ui/widgets/cache_indicator.dart';
export 'src/ui/widgets/playlist_panel.dart';
export 'src/ui/widgets/settings_sheet.dart';

// Utils
export 'src/utils/url_hasher.dart';
export 'src/utils/file_utils.dart';
export 'src/utils/size_formatter.dart';

// App
export 'src/cache_video_player.dart';
