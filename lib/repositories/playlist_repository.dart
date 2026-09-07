import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/database/hive_boxes.dart';
import '../models/audio_model.dart';
import '../models/playlist_model.dart';
import '../models/video_model.dart';
import 'media_repository.dart';

/// A playable queue resolved from a playlist — mixed video+audio playlists are
/// supported since the global player can switch modes between items.
class ResolvedPlaylistItem {
  final String mediaRef;
  final VideoModel? video;
  final AudioModel? audio;
  const ResolvedPlaylistItem({required this.mediaRef, this.video, this.audio});

  String get title => video?.title ?? audio?.title ?? 'Unknown';
  int get durationMs => video?.durationMs ?? audio?.durationMs ?? 0;
  bool get isVideo => video != null;
}

class PlaylistRepository {
  final MediaRepository mediaRepository;
  PlaylistRepository(this.mediaRepository);

  static const _uuid = Uuid();

  Box<PlaylistModel> get _box => Hive.box<PlaylistModel>(HiveBoxes.playlists);

  List<PlaylistModel> get userPlaylists =>
      _box.values.toList()..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

  PlaylistModel? byId(String id) => _box.get(id);

  Future<PlaylistModel> create(String name) async {
    final playlist = PlaylistModel(
      id: _uuid.v4(),
      name: name,
      mediaRefs: [],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await _box.put(playlist.id, playlist);
    return playlist;
  }

  Future<void> rename(String id, String newName) async {
    final p = _box.get(id);
    if (p == null) return;
    p.name = newName;
    await p.save();
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  Future<void> addMedia(String playlistId, String mediaRef) async {
    final p = _box.get(playlistId);
    if (p == null || p.mediaRefs.contains(mediaRef)) return;
    p.mediaRefs = [...p.mediaRefs, mediaRef];
    await p.save();
  }

  Future<void> removeMedia(String playlistId, String mediaRef) async {
    final p = _box.get(playlistId);
    if (p == null) return;
    p.mediaRefs = p.mediaRefs.where((r) => r != mediaRef).toList();
    await p.save();
  }

  Future<void> reorder(String playlistId, int oldIndex, int newIndex) async {
    final p = _box.get(playlistId);
    if (p == null) return;
    final refs = [...p.mediaRefs];
    final item = refs.removeAt(oldIndex);
    refs.insert(newIndex, item);
    p.mediaRefs = refs;
    await p.save();
  }

  List<ResolvedPlaylistItem> resolve(List<String> mediaRefs) {
    final resolved = <ResolvedPlaylistItem>[];
    for (final ref in mediaRefs) {
      final parts = ref.split(':');
      if (parts.length != 2) continue;
      final type = parts[0];
      final id = parts[1];
      if (type == 'video') {
        final v = mediaRepository.videoById(id);
        if (v != null && !v.isHidden) resolved.add(ResolvedPlaylistItem(mediaRef: ref, video: v));
      } else if (type == 'audio') {
        final a = mediaRepository.audioById(id);
        if (a != null && !a.isHidden) resolved.add(ResolvedPlaylistItem(mediaRef: ref, audio: a));
      }
    }
    return resolved;
  }

  /// Favorites, Recently Played and Most Played are computed live rather than
  /// stored, so they can never drift out of sync with the underlying library.
  List<ResolvedPlaylistItem> get favoritesQueue => [
        ...mediaRepository.favoriteVideos.map((v) => ResolvedPlaylistItem(mediaRef: v.mediaRef, video: v)),
        ...mediaRepository.favoriteAudio.map((a) => ResolvedPlaylistItem(mediaRef: a.mediaRef, audio: a)),
      ];

  List<ResolvedPlaylistItem> get recentlyPlayedQueue => [
        ...mediaRepository.recentlyPlayedVideos.map((v) => ResolvedPlaylistItem(mediaRef: v.mediaRef, video: v)),
        ...mediaRepository.recentlyPlayedAudio.map((a) => ResolvedPlaylistItem(mediaRef: a.mediaRef, audio: a)),
      ];

  List<ResolvedPlaylistItem> get mostPlayedQueue =>
      mediaRepository.mostPlayedAudio.map((a) => ResolvedPlaylistItem(mediaRef: a.mediaRef, audio: a)).toList();
}
