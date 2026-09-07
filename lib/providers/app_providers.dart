import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/download_task.dart';

import '../core/services/album_art_service.dart';
import '../core/services/audio_extraction_service.dart';
import '../core/services/audio_playback_handler.dart';
import '../core/services/download_manager.dart';
import '../core/services/native_download_runner.dart';
import '../core/services/equalizer_service.dart';
import '../core/services/media_mux_service.dart';
import '../core/services/global_player_controller.dart';
import '../core/services/media_scanner_service.dart';
import '../core/services/storage_scan_service.dart';
import '../core/services/youtube_native_service.dart';
import '../core/services/youtube_service.dart';
import '../repositories/media_repository.dart';
import '../repositories/download_repository.dart';
import '../repositories/eq_settings_repository.dart';
import '../repositories/playlist_repository.dart';
import '../repositories/safe_media_repository.dart';
import '../repositories/settings_repository.dart';

/// The audio_service handler must be created once via `AudioService.init(...)`
/// in main() before runApp — see main.dart. This provider is overridden with
/// that already-created instance at app startup so the rest of the app can
/// depend on it normally through Riverpod.
final audioHandlerProvider = Provider<AudioPlaybackHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden in main()');
});

final mediaScannerServiceProvider = Provider<MediaScannerService>((ref) => MediaScannerService());

final storageScanServiceProvider = Provider<StorageScanService>((ref) => StorageScanService());

final youtubeServiceProvider = Provider<YoutubeService>((ref) {
  final service = YoutubeService();
  ref.onDispose(service.dispose);
  return service;
});

/// Native yt-dlp bridge (com.prismplayer.app/ytdlp). Stateless wrapper, so a
/// single shared instance is fine — callers check `isAvailable()` before
/// relying on it, since the underlying Chaquopy runtime init can fail on a
/// given device/build.
final youtubeNativeServiceProvider = Provider<YoutubeNativeService>((ref) {
  return YoutubeNativeService();
});

/// Drives transfers through yt-dlp itself, so a resolved googlevideo URL is
/// never fetched from a different HTTP session than the one that signed it.
final nativeDownloadRunnerProvider = Provider<NativeDownloadRunner>((ref) {
  return NativeDownloadRunner(ref.watch(youtubeNativeServiceProvider));
});

final albumArtServiceProvider = Provider<AlbumArtService>((ref) => AlbumArtService());

final mediaMuxServiceProvider = Provider<MediaMuxService>((ref) => MediaMuxService());

final downloadRepositoryProvider = Provider<DownloadRepository>((ref) => DownloadRepository());

/// The download queue. Kept alive for the whole app session so transfers keep
/// running while the user browses away from the Downloads screen — closing that
/// screen must not cancel anything.
final downloadManagerProvider =
    StateNotifierProvider<DownloadManager, List<DownloadTask>>((ref) {
  return DownloadManager(
    repository: ref.watch(downloadRepositoryProvider),
    youtubeService: ref.watch(youtubeServiceProvider),
    nativeService: ref.watch(youtubeNativeServiceProvider),
    nativeRunner: ref.watch(nativeDownloadRunnerProvider),
    muxService: ref.watch(mediaMuxServiceProvider),
    scannerService: ref.watch(mediaScannerServiceProvider),
  );
});

/// Number of transfers currently in flight, for the badge on the Videos
/// screen's download button.
final activeDownloadCountProvider = Provider<int>((ref) {
  return ref.watch(downloadManagerProvider).where((t) => t.isPending).length;
});

final equalizerServiceProvider = Provider<EqualizerService>((ref) => EqualizerService());

final audioExtractionServiceProvider =
    Provider<AudioExtractionService>((ref) => AudioExtractionService());

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref.watch(mediaScannerServiceProvider));
});

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(ref.watch(mediaRepositoryProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => SettingsRepository());

final eqSettingsRepositoryProvider = Provider<EqSettingsRepository>((ref) => EqSettingsRepository());

final safeMediaRepositoryProvider = Provider<SafeMediaRepository>((ref) {
  return SafeMediaRepository(ref.watch(settingsRepositoryProvider));
});

final globalPlayerControllerProvider =
    StateNotifierProvider<GlobalPlayerController, PlayerUiState>((ref) {
  return GlobalPlayerController(
    audioHandler: ref.watch(audioHandlerProvider),
    equalizerService: ref.watch(equalizerServiceProvider),
    mediaRepository: ref.watch(mediaRepositoryProvider),
    settingsRepository: ref.watch(settingsRepositoryProvider),
    eqSettingsRepository: ref.watch(eqSettingsRepositoryProvider),
    albumArtService: ref.watch(albumArtServiceProvider),
    youtubeService: ref.watch(youtubeServiceProvider),
  );
});

/// Bumped after any library mutation (scan, hide, favorite, rename, delete)
/// that screens using plain Provider reads (rather than a Hive ValueListenable)
/// need to react to — e.g. computed cross-box data like Search results.
class LibraryRevisionNotifier extends StateNotifier<int> {
  LibraryRevisionNotifier() : super(0);
  void bump() => state = state + 1;
}

final libraryRevisionProvider =
    StateNotifierProvider<LibraryRevisionNotifier, int>((ref) => LibraryRevisionNotifier());
