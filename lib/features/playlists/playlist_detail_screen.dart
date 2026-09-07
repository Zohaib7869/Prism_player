import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/media_thumbnail.dart';
import '../../models/audio_model.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';
import '../../repositories/playlist_repository.dart';
import '../../routes/app_router.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;
  const PlaylistDetailScreen({super.key, required this.playlistId});

  bool get _isRecent => playlistId == '__recent__';
  bool get _isMostPlayed => playlistId == '__most_played__';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final playlistRepo = ref.watch(playlistRepositoryProvider);

    final String title;
    final List<ResolvedPlaylistItem> items;
    final bool editable;

    if (_isRecent) {
      title = 'Recently Played';
      items = playlistRepo.recentlyPlayedQueue;
      editable = false;
    } else if (_isMostPlayed) {
      title = 'Most Played';
      items = playlistRepo.mostPlayedQueue;
      editable = false;
    } else {
      final playlist = playlistRepo.byId(playlistId);
      title = playlist?.name ?? 'Playlist';
      items = playlistRepo.resolve(playlist?.mediaRefs ?? []);
      editable = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.shuffle_rounded),
              tooltip: 'Shuffle play',
              onPressed: () => _playAll(context, ref, items, shuffle: true),
            ),
        ],
      ),
      floatingActionButton: items.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: palette.accent,
              onPressed: () => _playAll(context, ref, items, shuffle: false),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play all'),
            ),
      body: items.isEmpty
          ? Center(child: Text('No items yet', style: TextStyle(color: palette.textMuted)))
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: items.length,
              onReorder: (oldIndex, newIndex) {
                if (!editable) return;
                if (newIndex > oldIndex) newIndex -= 1;
                playlistRepo.reorder(playlistId, oldIndex, newIndex);
              },
              itemBuilder: (context, i) {
                final item = items[i];
                return Padding(
                  key: ValueKey(item.mediaRef),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    tileColor: palette.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    leading: SizedBox(
                      width: 44, height: 44,
                      child: MediaThumbnail(
                        path: item.isVideo ? item.video!.thumbnailPath : item.audio!.albumArtUri,
                        isVideo: item.isVideo,
                        borderRadius: 8,
                      ),
                    ),
                    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(Formatters.duration(item.durationMs)),
                    trailing: editable
                        ? IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                            onPressed: () => playlistRepo.removeMedia(playlistId, item.mediaRef),
                          )
                        : null,
                    onTap: () => _playAt(context, ref, items, i),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _playAll(BuildContext context, WidgetRef ref, List<ResolvedPlaylistItem> items, {required bool shuffle}) async {
    await _playAt(context, ref, items, 0);
    if (shuffle) await ref.read(globalPlayerControllerProvider.notifier).toggleShuffle();
  }

  Future<void> _playAt(BuildContext context, WidgetRef ref, List<ResolvedPlaylistItem> items, int index) async {
    final controller = ref.read(globalPlayerControllerProvider.notifier);
    final videos = items.where((i) => i.isVideo).map((i) => i.video!).toList();
    final audios = items.where((i) => !i.isVideo).map((i) => i.audio!).toList();
    final target = items[index];

    if (target.isVideo) {
      await controller.playVideo(target.video!, queueVideos: videos.isEmpty ? [target.video!] : videos);
      if (context.mounted) context.push(AppRoutes.videoPlayer);
    } else {
      await controller.playAudio(target.audio!, queueAudio: audios.isEmpty ? [target.audio!] : audios);
      if (context.mounted) context.push(AppRoutes.audioPlayer);
    }
  }
}
