import 'package:flutter/foundation.dart';
import 'package:tostore/tostore.dart';

@internal
sealed class TableName {
  static const String mediaIndex = "flutter_cache_video_player_media_index";
  static const String chunkBitmap = "flutter_cache_video_player_chunk_bitmap";
  static const String playbackHistory = "flutter_cache_video_player_playback_history";
  static const String playerSettings = "flutter_cache_video_player_settings";
}

sealed class Tables {
  static List<TableSchema> allTables = [
    TableSchema(
      name: TableName.mediaIndex,
      tableId: 'flutter_cache_video_player_media_index',
      primaryKeyConfig: PrimaryKeyConfig(name: 'url_hash', type: PrimaryKeyType.none),
      fields: [
        FieldSchema(name: 'original_url', type: DataType.text, nullable: false),
        FieldSchema(name: 'local_dir', type: DataType.text, nullable: false),
        FieldSchema(name: 'total_bytes', type: DataType.integer, nullable: false),
        FieldSchema(name: 'mime_type', type: DataType.text, nullable: false),
        FieldSchema(name: 'is_completed', type: DataType.integer, defaultValue: 0),
        FieldSchema(name: 'created_at', type: DataType.integer, nullable: false),
        FieldSchema(name: 'last_accessed', type: DataType.integer, nullable: false),
        FieldSchema(name: 'total_chunks', type: DataType.integer, nullable: false),
      ],
    ),
    TableSchema(
      name: TableName.chunkBitmap,
      tableId: 'flutter_cache_video_player_chunk_bitmap',
      primaryKeyConfig: PrimaryKeyConfig(name: 'url_hash', type: PrimaryKeyType.none),
      fields: [
        FieldSchema(name: 'bitmap', type: DataType.blob, nullable: false),
        FieldSchema(name: 'downloaded_bytes', type: DataType.integer, defaultValue: 0),
      ],
    ),
    TableSchema(
      name: TableName.playbackHistory,
      tableId: 'flutter_cache_video_player_playback_history',
      primaryKeyConfig: PrimaryKeyConfig(name: 'id', type: PrimaryKeyType.sequential),
      fields: [
        FieldSchema(name: 'url_hash', type: DataType.text, nullable: false, createIndex: true),
        FieldSchema(name: 'position_ms', type: DataType.integer, nullable: false),
        FieldSchema(name: 'duration_ms', type: DataType.integer, nullable: false),
        FieldSchema(name: 'played_at', type: DataType.integer, nullable: false),
      ],
    ),
    TableSchema(
      name: TableName.playerSettings,
      tableId: 'flutter_cache_video_player_settings',
      primaryKeyConfig: PrimaryKeyConfig(name: 'key', type: PrimaryKeyType.none),
      fields: [FieldSchema(name: 'value', type: DataType.text, nullable: true)],
    ),
  ];
}
