import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'media_thumbnail.dart';

enum MediaCardLayout { grid, list }

/// Memoizes in-flight thumbnail generation per video id.
///
/// VideoCard is stateless (no local State to hold a Future across rebuilds),
/// and the Videos grid rebuilds every card whenever *any* single video's Hive
/// record changes (see videos_screen.dart's AnimatedBuilder on the whole
/// box) — including the very save that a thumbnail generation triggers when
/// it finishes. Without this cache, every such rebuild re-kicked off a fresh
/// native thumbnail extraction call for every card whose thumbnail hadn't
/// resolved *yet*, compounding: the more videos still pending, the more
/// duplicate native calls each rebuild fired, which is what made the video
/// list feel like it was lagging/freezing.
final Map<String, Future<String?>> _pendingThumbnailFutures = {};

/// Card for a single video, used across Home, Videos, Folders, Favorites and
/// search results. Long-press (or the trailing icon) opens the shared
/// MediaBottomSheet actions menu, wired by the caller via [onMore].
class VideoCard extends ConsumerWidget {
  final VideoModel video;
  final MediaCardLayout layout;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  const VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.onMore,
    this.layout = MediaCardLayout.grid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final progress = video.watchedFraction.clamp(0.0, 1.0);

    final thumbnail = AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video.thumbnailPath != null)
            MediaThumbnail(path: video.thumbnailPath, isVideo: true)
          else
            FutureBuilder<String?>(
              // thumbnailPath is only populated lazily (native thumbnail
              // generation is too slow to do for every video during a scan),
              // so the first time a card is built for a given video we
              // generate + cache it here and rebuild once it's ready. Reuse
              // any already-in-flight future for this video id instead of
              // starting a new native call on every rebuild — see
              // _pendingThumbnailFutures' doc comment.
              future: _pendingThumbnailFutures.putIfAbsent(
                video.id,
                () => ref.read(mediaRepositoryProvider).thumbnailFor(video).whenComplete(
                      () => _pendingThumbnailFutures.remove(video.id),
                    ),
              ),
              builder: (context, snapshot) {
                return MediaThumbnail(path: snapshot.data, isVideo: true);
              },
            ),
          Positioned(
            right: 6,
            bottom: progress > 0.02 ? 10 : 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                Formatters.duration(video.durationMs),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          if (progress > 0.02)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(palette.accent),
              ),
            ),
          if (video.isFavorite)
            Positioned(
              top: 6,
              left: 6,
              child: Icon(Icons.favorite_rounded, color: palette.accentSecondary, size: 16),
            ),
        ],
      ),
    );

    if (layout == MediaCardLayout.list) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 120, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: thumbnail)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${Formatters.fileSize(video.sizeBytes)} · ${Formatters.relativeDate(video.dateModifiedMs)}',
                      style: TextStyle(color: palette.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (onMore != null)
                IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: onMore),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onMore,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: thumbnail),
          const SizedBox(height: 6),
          Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          Text(Formatters.relativeDate(video.dateModifiedMs),
              style: TextStyle(color: palette.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
