import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart';

import '../../core/services/global_player_controller.dart';
import '../../models/queue_item.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';
import '../theme/app_theme.dart';
import 'audio_spectrum.dart';

/// Slim persistent bar shown across Home/Videos/Music/Folders whenever
/// something is loaded, whether playing or paused.
///
/// Audio mode keeps the classic art + title bar. Video mode renders a real
/// YouTube-style mini player: the live video surface keeps playing inside the
/// bar after the user leaves the full player screen, with play/pause,
/// previous/next, expand-to-fullscreen and an explicit close (X) that stops
/// playback completely.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(globalPlayerControllerProvider);
    final controller = ref.read(globalPlayerControllerProvider.notifier);
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final item = playerState.current;
    if (item == null) return const SizedBox.shrink();

    final progress = playerState.duration.inMilliseconds > 0
        ? (playerState.position.inMilliseconds / playerState.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final isVideo = playerState.mode == PlaybackMode.video;

    void openFullPlayer() {
      if (isVideo) {
        context.push(AppRoutes.videoPlayer);
      } else {
        context.push(AppRoutes.audioPlayer);
      }
    }

    return GestureDetector(
      onTap: openFullPlayer,
      child: Container(
        height: isVideo ? 76 : 64,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  if (isVideo)
                    _MiniVideoSurface(state: playerState, palette: palette, item: item)
                  else ...[
                    _MiniArt(item: item, palette: palette),
                    const SizedBox(width: 10),
                    MiniSpectrumBars(playing: playerState.isPlaying, color: palette.accent),
                  ],
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        if (item.artist != null)
                          Text(
                            item.artist!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.textMuted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.skip_previous_rounded, color: palette.textPrimary),
                    onPressed: playerState.hasPrevious ? controller.skipPrevious : null,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      playerState.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      color: palette.accent,
                      size: 34,
                    ),
                    onPressed: controller.togglePlayPause,
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.skip_next_rounded, color: palette.textPrimary),
                    onPressed: playerState.hasNext ? controller.skipNext : null,
                  ),
                  if (isVideo)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Fullscreen',
                      icon: Icon(Icons.fullscreen_rounded, color: palette.textPrimary),
                      onPressed: openFullPlayer,
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Close player',
                    icon: Icon(Icons.close_rounded, color: palette.textMuted),
                    onPressed: controller.stopAndClear,
                  ),
                  const SizedBox(width: 2),
                ],
              ),
            ),
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: palette.divider,
              valueColor: AlwaysStoppedAnimation(palette.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// The live video picture inside the mini player. Reuses the *same*
/// controller the full-screen player uses, so nothing restarts or re-buffers
/// when the user moves between the two — playback simply continues.
class _MiniVideoSurface extends StatelessWidget {
  final PlayerUiState state;
  final PrismPalette palette;
  final QueueItem item;
  const _MiniVideoSurface({required this.state, required this.palette, required this.item});

  @override
  Widget build(BuildContext context) {
    final mkController = state.mkVideoController;
    final videoController = state.videoController;

    Widget content;
    if (mkController != null) {
      content = mkv.Video(
        controller: mkController,
        fit: BoxFit.cover,
        controls: mkv.NoVideoControls,
      );
    } else if (videoController != null) {
      content = FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: videoController.value.size.width == 0 ? 16 : videoController.value.size.width,
          height: videoController.value.size.height == 0 ? 9 : videoController.value.size.height,
          child: VideoPlayer(videoController),
        ),
      );
    } else {
      content = Container(
        color: Colors.black,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 96,
        height: 56,
        color: Colors.black,
        child: content,
      ),
    );
  }
}

class _MiniArt extends StatelessWidget {
  final QueueItem item;
  final PrismPalette palette;
  const _MiniArt({required this.item, required this.palette});

  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
          color: palette.surface,
          child: Icon(
            item.isVideo ? Icons.movie_rounded : Icons.music_note_rounded,
            color: palette.textMuted,
          ),
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 48,
        height: 48,
        child: (item.artUri != null && item.artUri!.startsWith('/'))
            ? Image.file(File(item.artUri!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback())
            : (item.artUri != null && item.artUri!.startsWith('http'))
                ? Image.network(item.artUri!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback())
                : fallback(),
      ),
    );
  }
}
