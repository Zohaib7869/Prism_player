import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../models/audio_model.dart';
import '../theme/app_theme.dart';

/// List-row card for a single song, used across Home, Music, Playlists,
/// Favorites and search results.
///
/// Deliberately does NOT render album-art thumbnails: each row used to carry
/// a MediaThumbnail (content:// album art decode via a native call, or a
/// FutureBuilder while it loaded). With long lists this meant dozens of
/// concurrent async decodes kicking off as the list scrolled, which was the
/// main cause of the song-list scroll lag. A plain themed icon is instant
/// and never blocks the list.
class AudioCard extends StatelessWidget {
  final AudioModel audio;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final bool showAlbum;
  final Widget? trailing;

  const AudioCard({
    super.key,
    required this.audio,
    required this.onTap,
    this.onMore,
    this.showAlbum = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.surfaceElevated, palette.surface],
                ),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.music_note_rounded, color: palette.textMuted, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (audio.isFavorite)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.favorite_rounded, size: 13, color: palette.accentSecondary),
                        ),
                      Expanded(
                        child: Text(audio.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    showAlbum ? '${audio.artist} · ${audio.album}' : audio.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(Formatters.duration(audio.durationMs), style: TextStyle(color: palette.textMuted, fontSize: 12)),
            if (trailing != null) trailing!,
            if (onMore != null)
              IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: onMore, iconSize: 20),
          ],
        ),
      ),
    );
  }
}
