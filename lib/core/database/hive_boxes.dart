import 'package:hive_flutter/hive_flutter.dart';

import '../../models/audio_model.dart';
import '../../models/download_task.dart';
import '../../models/eq_settings_model.dart';
import '../../models/playback_history_entry.dart';
import '../../models/playlist_model.dart';
import '../../models/video_model.dart';

/// Central place for every Hive box name so repositories never hard-code strings.
class HiveBoxes {
  HiveBoxes._();

  static const String videos = 'videos_box';
  static const String audio = 'audio_box';
  static const String playlists = 'playlists_box';
  static const String history = 'history_box';
  static const String eqSettings = 'eq_settings_box';
  static const String favorites = 'favorites_box'; // Map<mediaRef, bool>
  static const String hiddenMedia = 'hidden_media_box'; // Map<mediaRef, bool>
  static const String hiddenFolders = 'hidden_folders_box'; // Map<folderPath, bool>
  static const String appSettings = 'app_settings_box'; // generic key/value
  static const String scanMeta = 'scan_meta_box'; // last-scan timestamps
  static const String downloads = 'downloads_box'; // YouTube download queue + history
}

/// Boots Hive, registers every hand-written TypeAdapter and opens every box.
/// Call once from `main()` before `runApp`.
class AppDatabase {
  AppDatabase._();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();

    Hive.registerAdapter(VideoModelAdapter());
    Hive.registerAdapter(AudioModelAdapter());
    Hive.registerAdapter(PlaylistModelAdapter());
    Hive.registerAdapter(PlaybackHistoryEntryAdapter());
    Hive.registerAdapter(EqSettingsModelAdapter());
    Hive.registerAdapter(DownloadTaskAdapter());

    await Future.wait([
      Hive.openBox<VideoModel>(HiveBoxes.videos),
      Hive.openBox<AudioModel>(HiveBoxes.audio),
      Hive.openBox<PlaylistModel>(HiveBoxes.playlists),
      Hive.openBox<PlaybackHistoryEntry>(HiveBoxes.history),
      Hive.openBox<EqSettingsModel>(HiveBoxes.eqSettings),
      Hive.openBox<DownloadTask>(HiveBoxes.downloads),
      Hive.openBox(HiveBoxes.favorites),
      Hive.openBox(HiveBoxes.hiddenMedia),
      Hive.openBox(HiveBoxes.hiddenFolders),
      Hive.openBox(HiveBoxes.appSettings),
      Hive.openBox(HiveBoxes.scanMeta),
    ]);

    _initialized = true;
  }
}
