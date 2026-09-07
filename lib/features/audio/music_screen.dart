import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_boxes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/audio_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/media_bottom_sheet.dart';
import '../../core/widgets/playlist_picker_sheet.dart';
import '../../models/audio_model.dart';
import '../../providers/app_providers.dart';
import '../../repositories/media_repository.dart';
import '../../routes/app_router.dart';
import '../player/widgets/file_info_sheet.dart';

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 6, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music'),
        actions: [IconButton(icon: const Icon(Icons.search_rounded), onPressed: () => context.push(AppRoutes.search))],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Songs'),
            Tab(text: 'Artists'),
            Tab(text: 'Albums'),
            Tab(text: 'Genres'),
            Tab(text: 'Folders'),
            Tab(text: 'Recent'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: Hive.box<AudioModel>(HiveBoxes.audio).listenable(),
        builder: (context, _) {
          return TabBarView(
            controller: _tabController,
            children: [
              _SongsTab(),
              _GroupedTab(groupOf: (repo) => repo.audioByArtist, icon: Icons.person_rounded),
              _GroupedTab(groupOf: (repo) => repo.audioByAlbum, icon: Icons.album_rounded),
              _GroupedTab(groupOf: (repo) => repo.audioByGenre, icon: Icons.category_rounded),
              const _FoldersTabRedirect(),
              _RecentTab(),
            ],
          );
        },
      ),
    );
  }
}

class _SongsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    final songs = repo.allAudio;
    if (songs.isEmpty) {
      return const EmptyState(icon: Icons.music_note_outlined, title: 'No music found',
          message: 'Audio files on your device will show up here.');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: songs.length,
      itemBuilder: (context, i) => AudioCard(
        audio: songs[i],
        onTap: () async {
          await ref.read(globalPlayerControllerProvider.notifier).playAudio(songs[i], queueAudio: songs, startIndex: i);
          if (context.mounted) context.push(AppRoutes.audioPlayer);
        },
        onMore: () => _showSongActions(context, ref, songs[i]),
      ),
    );
  }
}

class _RecentTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    final songs = repo.recentlyPlayedAudio;
    if (songs.isEmpty) {
      return const EmptyState(icon: Icons.history_rounded, title: 'Nothing played yet');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: songs.length,
      itemBuilder: (context, i) => AudioCard(
        audio: songs[i],
        onTap: () async {
          await ref.read(globalPlayerControllerProvider.notifier).playAudio(songs[i], queueAudio: songs, startIndex: i);
          if (context.mounted) context.push(AppRoutes.audioPlayer);
        },
      ),
    );
  }
}

class _GroupedTab extends ConsumerWidget {
  final Map<String, List<AudioModel>> Function(MediaRepository repo) groupOf;
  final IconData icon;
  _GroupedTab({required this.groupOf, required this.icon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final groups = groupOf(repo);
    if (groups.isEmpty) return const EmptyState(icon: Icons.music_note_outlined, title: 'No music found');
    final keys = groups.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final key = keys[i];
        final items = groups[key]!;
        return ListTile(
          leading: CircleAvatar(backgroundColor: palette.surface, child: Icon(icon, color: palette.accent)),
          title: Text(key, style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
          subtitle: Text('${items.length} songs', style: TextStyle(color: palette.textMuted)),
          onTap: () => _showGroupSheet(context, ref, key, items),
        );
      },
    );
  }

  void _showGroupSheet(BuildContext context, WidgetRef ref, String title, List<AudioModel> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: items.length,
                itemBuilder: (context, i) => AudioCard(
                  audio: items[i],
                  showAlbum: false,
                  onTap: () async {
                    Navigator.pop(context);
                    await ref.read(globalPlayerControllerProvider.notifier).playAudio(items[i], queueAudio: items, startIndex: i);
                    if (context.mounted) context.push(AppRoutes.audioPlayer);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoldersTabRedirect extends StatelessWidget {
  const _FoldersTabRedirect();
  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Center(
      child: TextButton.icon(
        onPressed: () => context.push(AppRoutes.folders),
        icon: Icon(Icons.folder_rounded, color: palette.accent),
        label: Text('Browse by folder', style: TextStyle(color: palette.accent)),
      ),
    );
  }
}

void _showSongActions(BuildContext context, WidgetRef ref, AudioModel audio) {
  final repo = ref.read(mediaRepositoryProvider);
  showMediaBottomSheet(
    context: context,
    title: audio.title,
    subtitle: audio.artist,
    actions: [
      SheetAction(
        icon: Icons.play_arrow_rounded,
        label: 'Play',
        onTap: () async {
          await ref.read(globalPlayerControllerProvider.notifier).playAudio(audio);
          if (context.mounted) context.push(AppRoutes.audioPlayer);
        },
      ),
      SheetAction(
        icon: audio.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        label: audio.isFavorite ? 'Remove from favorites' : 'Add to favorites',
        onTap: () => repo.toggleAudioFavorite(audio.id),
      ),
      SheetAction(
        icon: Icons.playlist_add_rounded,
        label: 'Add to playlist',
        onTap: () => showPlaylistPickerSheet(context: context, ref: ref, mediaRef: audio.mediaRef),
      ),
      SheetAction(
        icon: Icons.drive_file_rename_outline_rounded,
        label: 'Rename',
        onTap: () async {
          final newName = await showTextInputDialog(context: context, title: 'Rename', initialValue: audio.title);
          if (newName != null && newName.isNotEmpty) await repo.renameAudio(audio.id, newName);
        },
      ),
      SheetAction(
        icon: Icons.info_outline_rounded,
        label: 'File information',
        onTap: () => showFileInfoSheet(context: context, audio: audio),
      ),
      SheetAction(
        icon: Icons.visibility_off_rounded,
        label: 'Hide (move to Safe)',
        onTap: () => repo.setAudioHidden(audio.id, true),
      ),
      SheetAction(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        destructive: true,
        onTap: () async {
          final confirmed = await showConfirmDialog(
              context: context, title: 'Delete song', message: 'This permanently deletes "${audio.title}" from your device.');
          if (confirmed == true) await repo.deleteAudio(audio.id);
        },
      ),
    ],
  );
}
