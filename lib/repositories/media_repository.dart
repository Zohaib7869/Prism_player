import 'package:hive_flutter/hive_flutter.dart';

import '../core/database/hive_boxes.dart';
import '../core/services/media_scanner_service.dart';
import '../models/audio_model.dart';
import '../models/folder_summary.dart';
import '../models/video_model.dart';

class SearchResults {
  final List<VideoModel> videos;
  final List<AudioModel> songs;
  final List<String> artists;
  final List<String> albums;
  final List<FolderSummary> folders;

  const SearchResults({
    required this.videos,
    required this.songs,
    required this.artists,
    required this.albums,
    required this.folders,
  });

  bool get isEmpty =>
      videos.isEmpty && songs.isEmpty && artists.isEmpty && albums.isEmpty && folders.isEmpty;
}

/// Owns all scanned media: the source of truth for Videos, Music and Folders
/// screens, favorites, hidden/safe state, and search. Talks to MediaStore only
/// through [MediaScannerService]; everything else is local Hive reads/writes.
class MediaRepository {
  final MediaScannerService scannerService;
  MediaRepository(this.scannerService);

  Box<VideoModel> get _videoBox => Hive.box<VideoModel>(HiveBoxes.videos);
  Box<AudioModel> get _audioBox => Hive.box<AudioModel>(HiveBoxes.audio);
  Box get _favBox => Hive.box(HiveBoxes.favorites);
  Box get _hiddenBox => Hive.box(HiveBoxes.hiddenMedia);
  Box get _hiddenFoldersBox => Hive.box(HiveBoxes.hiddenFolders);
  Box get _scanMetaBox => Hive.box(HiveBoxes.scanMeta);

  // ---------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------

  /// Incrementally scans MediaStore for anything changed since the last scan
  /// and upserts it into the local database. Pass [fullRescan] to ignore the
  /// stored watermark (e.g. user tapped "Scan media" in Settings).
  Future<void> scan({bool fullRescan = false}) async {
    final since = fullRescan ? 0 : (_scanMetaBox.get('lastScanMs', defaultValue: 0) as int);
    final scanStartedAt = DateTime.now().millisecondsSinceEpoch;

    final videoMaps = await scannerService.scanVideos(sinceEpochMs: since);
    final audioMaps = await scannerService.scanAudio(sinceEpochMs: since);
    await applyScanResult(videoMaps, audioMaps);

    await _scanMetaBox.put('lastScanMs', scanStartedAt);
  }

  /// Upserts an already-fetched batch of raw MediaStore maps (e.g. the final
  /// payload from a [StorageScanService] full scan) into the local database,
  /// preserving user state (favorites, hidden, watch progress) for existing
  /// entries — same merge logic [scan] uses.
  Future<void> applyScanResult(
    List<Map<dynamic, dynamic>> videoMaps,
    List<Map<dynamic, dynamic>> audioMaps,
  ) async {
    for (final map in videoMaps) {
      final model = VideoModel.fromScanMap(map);
      final existing = _videoBox.get(model.id);
      if (existing != null) {
        existing.title = model.title;
        model.lastPositionMs = existing.lastPositionMs;
        model.watchedFraction = existing.watchedFraction;
        model.playCount = existing.playCount;
        model.isFavorite = existing.isFavorite;
        model.isHidden = existing.isHidden;
        model.lastPlayedAtMs = existing.lastPlayedAtMs;
        model.thumbnailPath = existing.thumbnailPath;
      }
      await _videoBox.put(model.id, model);
    }

    for (final map in audioMaps) {
      final model = AudioModel.fromScanMap(map);
      final existing = _audioBox.get(model.id);
      if (existing != null) {
        model.lastPositionMs = existing.lastPositionMs;
        model.playCount = existing.playCount;
        model.isFavorite = existing.isFavorite;
        model.isHidden = existing.isHidden;
        model.lastPlayedAtMs = existing.lastPlayedAtMs;
        model.isExtracted = existing.isExtracted;
      }
      await _audioBox.put(model.id, model);
    }

    await _scanMetaBox.put('lastScanMs', DateTime.now().millisecondsSinceEpoch);
  }

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  List<VideoModel> get allVideos =>
      _videoBox.values.where((v) => !v.isHidden).toList()
        ..sort((a, b) => b.dateModifiedMs.compareTo(a.dateModifiedMs));

  List<AudioModel> get allAudio =>
      _audioBox.values.where((a) => !a.isHidden).toList()
        ..sort((a, b) => b.dateModifiedMs.compareTo(a.dateModifiedMs));

  List<VideoModel> get hiddenVideos => _videoBox.values.where((v) => v.isHidden).toList();
  List<AudioModel> get hiddenAudio => _audioBox.values.where((a) => a.isHidden).toList();

  List<VideoModel> get favoriteVideos => allVideos.where((v) => v.isFavorite).toList();
  List<AudioModel> get favoriteAudio => allAudio.where((a) => a.isFavorite).toList();

  List<VideoModel> get recentlyPlayedVideos {
    final list = allVideos.where((v) => v.lastPlayedAtMs > 0).toList();
    list.sort((a, b) => b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs));
    return list;
  }

  List<AudioModel> get recentlyPlayedAudio {
    final list = allAudio.where((a) => a.lastPlayedAtMs > 0).toList();
    list.sort((a, b) => b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs));
    return list;
  }

  /// "Continue Watching" = videos with meaningful, unfinished progress.
  List<VideoModel> get continueWatching {
    final list = allVideos
        .where((v) => v.watchedFraction > 0.02 && v.watchedFraction < 0.95)
        .toList();
    list.sort((a, b) => b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs));
    return list;
  }

  List<AudioModel> get mostPlayedAudio {
    final list = allAudio.where((a) => a.playCount > 0).toList();
    list.sort((a, b) => b.playCount.compareTo(a.playCount));
    return list;
  }

  VideoModel? videoById(String id) => _videoBox.get(id);
  AudioModel? audioById(String id) => _audioBox.get(id);

  Map<String, List<AudioModel>> get audioByArtist {
    final map = <String, List<AudioModel>>{};
    for (final a in allAudio) {
      map.putIfAbsent(a.artist, () => []).add(a);
    }
    return map;
  }

  Map<String, List<AudioModel>> get audioByAlbum {
    final map = <String, List<AudioModel>>{};
    for (final a in allAudio) {
      map.putIfAbsent(a.album, () => []).add(a);
    }
    return map;
  }

  Map<String, List<AudioModel>> get audioByGenre {
    final map = <String, List<AudioModel>>{};
    for (final a in allAudio) {
      map.putIfAbsent(a.genre ?? 'Unknown Genre', () => []).add(a);
    }
    return map;
  }

  List<FolderSummary> get videoFolders => _foldersOf(allVideos, const []);
  List<FolderSummary> get audioFolders => _foldersOf(const [], allAudio);

  List<FolderSummary> get allFolders => _foldersOf(allVideos, allAudio);

  List<FolderSummary> _foldersOf(List<VideoModel> videos, List<AudioModel> audio) {
    final byPath = <String, FolderSummary>{};
    void addVideo(VideoModel v) {
      final existing = byPath[v.folderPath];
      byPath[v.folderPath] = FolderSummary(
        path: v.folderPath,
        name: v.folderName,
        videoCount: (existing?.videoCount ?? 0) + 1,
        audioCount: existing?.audioCount ?? 0,
        totalSizeBytes: (existing?.totalSizeBytes ?? 0) + v.sizeBytes,
        previewThumbnailPath: existing?.previewThumbnailPath ?? v.thumbnailPath,
        isHidden: isFolderHidden(v.folderPath),
      );
    }

    void addAudio(AudioModel a) {
      final existing = byPath[a.folderPath];
      byPath[a.folderPath] = FolderSummary(
        path: a.folderPath,
        name: a.folderName,
        videoCount: existing?.videoCount ?? 0,
        audioCount: (existing?.audioCount ?? 0) + 1,
        totalSizeBytes: (existing?.totalSizeBytes ?? 0) + a.sizeBytes,
        previewThumbnailPath: existing?.previewThumbnailPath,
        isHidden: isFolderHidden(a.folderPath),
      );
    }

    for (final v in videos) {
      addVideo(v);
    }
    for (final a in audio) {
      addAudio(a);
    }
    final list = byPath.values.where((f) => !f.isHidden).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<VideoModel> videosInFolder(String folderPath) =>
      allVideos.where((v) => v.folderPath == folderPath).toList();

  List<AudioModel> audioInFolder(String folderPath) =>
      allAudio.where((a) => a.folderPath == folderPath).toList();

  // ---------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------

  SearchResults search(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return const SearchResults(videos: [], songs: [], artists: [], albums: [], folders: []);
    }
    final videos = allVideos.where((v) => v.title.toLowerCase().contains(query)).toList();
    final songs = allAudio
        .where((a) =>
            a.title.toLowerCase().contains(query) ||
            a.artist.toLowerCase().contains(query) ||
            a.album.toLowerCase().contains(query))
        .toList();
    final artists = audioByArtist.keys.where((a) => a.toLowerCase().contains(query)).toList();
    final albums = audioByAlbum.keys.where((a) => a.toLowerCase().contains(query)).toList();
    final folders = allFolders.where((f) => f.name.toLowerCase().contains(query)).toList();
    return SearchResults(videos: videos, songs: songs, artists: artists, albums: albums, folders: folders);
  }

  // ---------------------------------------------------------------------
  // Favorites / Hidden toggles
  // ---------------------------------------------------------------------

  Future<void> toggleVideoFavorite(String id) async {
    final v = _videoBox.get(id);
    if (v == null) return;
    v.isFavorite = !v.isFavorite;
    await v.save();
    await _favBox.put(v.mediaRef, v.isFavorite);
  }

  Future<void> toggleAudioFavorite(String id) async {
    final a = _audioBox.get(id);
    if (a == null) return;
    a.isFavorite = !a.isFavorite;
    await a.save();
    await _favBox.put(a.mediaRef, a.isFavorite);
  }

  Future<void> setVideoHidden(String id, bool hidden) async {
    final v = _videoBox.get(id);
    if (v == null) return;
    v.isHidden = hidden;
    await v.save();
    await _hiddenBox.put(v.mediaRef, hidden);
  }

  Future<void> setAudioHidden(String id, bool hidden) async {
    final a = _audioBox.get(id);
    if (a == null) return;
    a.isHidden = hidden;
    await a.save();
    await _hiddenBox.put(a.mediaRef, hidden);
  }

  bool isFolderHidden(String path) => _hiddenFoldersBox.get(path, defaultValue: false) as bool;

  Future<void> setFolderHidden(String path, bool hidden) async {
    await _hiddenFoldersBox.put(path, hidden);
    // Hiding a folder hides every item inside it too, without touching files on disk.
    for (final v in _videoBox.values.where((v) => v.folderPath == path)) {
      v.isHidden = hidden;
      await v.save();
    }
    for (final a in _audioBox.values.where((a) => a.folderPath == path)) {
      a.isHidden = hidden;
      await a.save();
    }
  }

  // ---------------------------------------------------------------------
  // Playback bookkeeping
  // ---------------------------------------------------------------------

  Future<void> recordVideoProgress(String id, int positionMs, int durationMs) async {
    final v = _videoBox.get(id);
    if (v == null) return;
    v.lastPositionMs = positionMs;
    v.watchedFraction = durationMs > 0 ? (positionMs / durationMs).clamp(0, 1) : 0;
    v.lastPlayedAtMs = DateTime.now().millisecondsSinceEpoch;
    await v.save();
  }

  Future<void> recordVideoPlayed(String id) async {
    final v = _videoBox.get(id);
    if (v == null) return;
    v.playCount += 1;
    v.lastPlayedAtMs = DateTime.now().millisecondsSinceEpoch;
    await v.save();
  }

  Future<void> recordAudioProgress(String id, int positionMs) async {
    final a = _audioBox.get(id);
    if (a == null) return;
    a.lastPositionMs = positionMs;
    await a.save();
  }

  Future<void> recordAudioPlayed(String id) async {
    final a = _audioBox.get(id);
    if (a == null) return;
    a.playCount += 1;
    a.lastPlayedAtMs = DateTime.now().millisecondsSinceEpoch;
    await a.save();
  }

  // ---------------------------------------------------------------------
  // File management
  // ---------------------------------------------------------------------

  Future<bool> renameVideo(String id, String newFileName) async {
    final v = _videoBox.get(id);
    if (v == null) return false;
    final ok = await scannerService.renameFile(v.path, newFileName);
    if (ok) {
      v.title = newFileName;
      await v.save();
    }
    return ok;
  }

  Future<bool> renameAudio(String id, String newFileName) async {
    final a = _audioBox.get(id);
    if (a == null) return false;
    final ok = await scannerService.renameFile(a.path, newFileName);
    if (ok) {
      a.title = newFileName;
      await a.save();
    }
    return ok;
  }

  Future<bool> deleteVideo(String id) async {
    final v = _videoBox.get(id);
    if (v == null) return false;
    final ok = await scannerService.deleteFile(v.path);
    if (ok) await v.delete();
    return ok;
  }

  Future<bool> deleteAudio(String id) async {
    final a = _audioBox.get(id);
    if (a == null) return false;
    final ok = await scannerService.deleteFile(a.path);
    if (ok) await a.delete();
    return ok;
  }

  Future<String?> thumbnailFor(VideoModel video) async {
    if (video.thumbnailPath != null) return video.thumbnailPath;
    final path = await scannerService.videoThumbnail(video.path, video.id);
    if (path != null) {
      video.thumbnailPath = path;
      await video.save();
    }
    return path;
  }

  /// Registers a freshly-extracted "Save as Audio" file so it immediately
  /// shows up in the Music section without waiting for the next MediaStore scan.
  Future<void> registerExtractedAudio(AudioModel model) async {
    model.isExtracted = true;
    await _audioBox.put(model.id, model);
  }
}
