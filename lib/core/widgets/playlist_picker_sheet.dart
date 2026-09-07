import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'media_bottom_sheet.dart';

/// Bottom sheet used by "Add to playlist" actions: lists existing playlists
/// plus a "New playlist" entry, and adds [mediaRef] to whichever is picked.
Future<void> showPlaylistPickerSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String mediaRef,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  final playlistRepo = ref.read(playlistRepositoryProvider);
  final playlists = playlistRepo.userPlaylists;

  return showModalBottomSheet(
    context: context,
    backgroundColor: palette.surfaceElevated,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Add to playlist', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(
              leading: Icon(Icons.add_circle_rounded, color: palette.accent),
              title: const Text('New playlist'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final name = await showTextInputDialog(context: context, title: 'New playlist', initialValue: '', hint: 'Playlist name');
                if (name == null || name.isEmpty) return;
                final playlist = await playlistRepo.create(name);
                await playlistRepo.addMedia(playlist.id, mediaRef);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to "$name"')));
                }
              },
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, i) {
                  final p = playlists[i];
                  return ListTile(
                    leading: Icon(Icons.playlist_play_rounded, color: palette.textPrimary),
                    title: Text(p.name),
                    subtitle: Text('${p.mediaRefs.length} items'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await playlistRepo.addMedia(p.id, mediaRef);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added to "${p.name}"')));
                      }
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}
