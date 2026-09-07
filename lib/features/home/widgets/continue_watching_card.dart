import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../../models/video_model.dart';
import '../../../providers/app_providers.dart';
import '../../../routes/app_router.dart';

class ContinueWatchingCard extends ConsumerWidget {
  final VideoModel video;
  const ContinueWatchingCard({super.key, required this.video});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return GestureDetector(
      onTap: () async {
        await ref.read(globalPlayerControllerProvider.notifier).playVideo(video);
        if (context.mounted) context.push(AppRoutes.videoPlayer);
      },
      child: SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaThumbnail(path: video.thumbnailPath, isVideo: true),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                    ),
                  ),
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: LinearProgressIndicator(
                      value: video.watchedFraction.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation(palette.accent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            Text('${Formatters.duration(video.lastPositionMs)} of ${Formatters.duration(video.durationMs)}',
                style: TextStyle(color: palette.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
