import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_boxes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_bottom_sheet.dart';
import '../../core/widgets/playlist_card.dart';
import '../../models/playlist_model.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final playlistRepo = ref.watch(playlistRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: palette.accent,
        onPressed: () async {
          final name = await showTextInputDialog(context: context, title: 'New playlist', initialValue: '', hint: 'Playlist name');
          if (name != null && name.isNotEmpty) await playlistRepo.create(name);
        },
        child: const Icon(Icons.add_rounded),
      ),
      body: AnimatedBuilder(
        animation: Hive.box<PlaylistModel>(HiveBoxes.playlists).listenable(),
        builder: (context, _) {
          final userPlaylists = playlistRepo.userPlaylists;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              Text('Smart playlists', style: TextStyle(color: palette.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              PlaylistCard(
                name: 'Favorites',
                icon: Icons.favorite_rounded,
                itemCount: playlistRepo.favoritesQueue.length,
                onTap: () => context.push(AppRoutes.favorites),
              ),
              const SizedBox(height: 10),
              PlaylistCard(
                name: 'Recently Played',
                icon: Icons.history_rounded,
                itemCount: playlistRepo.recentlyPlayedQueue.length,
                onTap: () => context.push('${AppRoutes.playlists}/detail', extra: '__recent__'),
              ),
              const SizedBox(height: 10),
              PlaylistCard(
                name: 'Most Played',
                icon: Icons.trending_up_rounded,
                itemCount: playlistRepo.mostPlayedQueue.length,
                onTap: () => context.push('${AppRoutes.playlists}/detail', extra: '__most_played__'),
              ),
              const SizedBox(height: 20),
              Text('Your playlists', style: TextStyle(color: palette.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (userPlaylists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No playlists yet. Tap + to create one.', style: TextStyle(color: palette.textMuted))),
                ),
              for (final p in userPlaylists)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PlaylistCard(
                    name: p.name,
                    itemCount: p.mediaRefs.length,
                    onTap: () => context.push('${AppRoutes.playlists}/detail', extra: p.id),
                    onMore: () => showMediaBottomSheet(
                      context: context,
                      title: p.name,
                      subtitle: '${p.mediaRefs.length} items',
                      actions: [
                        SheetAction(
                          icon: Icons.drive_file_rename_outline_rounded,
                          label: 'Rename',
                          onTap: () async {
                            final name = await showTextInputDialog(context: context, title: 'Rename playlist', initialValue: p.name);
                            if (name != null && name.isNotEmpty) await playlistRepo.rename(p.id, name);
                          },
                        ),
                        SheetAction(
                          icon: Icons.delete_outline_rounded,
                          label: 'Delete playlist',
                          destructive: true,
                          onTap: () async {
                            final confirmed = await showConfirmDialog(
                                context: context, title: 'Delete playlist', message: 'Delete "${p.name}"? This does not delete the media files.');
                            if (confirmed == true) await playlistRepo.delete(p.id);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
