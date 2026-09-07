import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/global_player_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/audio_spectrum.dart';
import '../../core/widgets/media_bottom_sheet.dart';
import '../../core/widgets/media_thumbnail.dart';
import '../../core/widgets/playlist_picker_sheet.dart';
import '../../models/queue_item.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';
import 'widgets/file_info_sheet.dart';
import 'widgets/playback_speed_sheet.dart';
import 'widgets/queue_sheet.dart';
import 'widgets/save_as_audio_dialog.dart';
import 'widgets/volume_booster_sheet.dart';

class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  VisualizerStyle _style = VisualizerStyle.rotatingDisk;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(settingsRepositoryProvider).visualizerStyleIndex;
    _style = VisualizerStyle.values[saved.clamp(0, VisualizerStyle.values.length - 1)];
  }

  void _cycleStyle() {
    final next = VisualizerStyle.values[(_style.index + 1) % VisualizerStyle.values.length];
    setState(() => _style = next);
    ref.read(settingsRepositoryProvider).visualizerStyleIndex = next.index;
  }

  @override
  Widget build(BuildContext context) {
    // Position/duration tick ~4x/sec while playing (see GlobalPlayerController's
    // _positionTicker). Watching the whole PlayerUiState here used to rebuild
    // this entire screen (Hero art, buttons, everything) on every tick, which
    // flashed the album art and made the push-in transition look stuck. This
    // selects only the fields this part of the screen actually needs — the
    // record's structural equality means Riverpod skips the rebuild when only
    // position/duration changed. Position/duration themselves are watched
    // separately, only by the small _Scrubber below.
    final playerState = ref.watch(globalPlayerControllerProvider.select((s) => (
          current: s.current,
          isPlaying: s.isPlaying,
          speed: s.speed,
          repeat: s.repeat,
          shuffle: s.shuffle,
          hasNext: s.hasNext,
          hasPrevious: s.hasPrevious,
        )));
    final controller = ref.read(globalPlayerControllerProvider.notifier);
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final item = playerState.current;
    final mediaRepo = ref.read(mediaRepositoryProvider);

    if (item == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.pop();
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final audio = mediaRepo.audioById(item.mediaId);
    final isFavorite = audio?.isFavorite ?? false;

    return Scaffold(
      // Transparent so the app-wide wallpaper/gradient from PrismBackground
      // (installed once in MaterialApp.builder) shows through here too —
      // this screen used to paint over it with a flat palette.background.
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded), onPressed: () => context.pop()),
        title: Text(item.isVideo ? 'Playing as Audio' : 'Now Playing', style: const TextStyle(fontSize: 14)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Visualizer: ${_style.label}',
            icon: Icon(_style.icon),
            onPressed: _cycleStyle,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showMoreSheet(context, ref, item),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),
              Hero(
                tag: 'player-art',
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _VisualizerArt(
                    style: _style,
                    item: item,
                    playing: playerState.isPlaying,
                    palette: palette,
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: palette.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
                        if (item.artist != null) ...[
                          const SizedBox(height: 4),
                          Text(item.artist!, style: TextStyle(color: palette.textMuted, fontSize: 14)),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFavorite ? palette.accentSecondary : palette.textMuted),
                    onPressed: () {
                      if (item.isVideo) {
                        mediaRepo.toggleVideoFavorite(item.mediaId);
                      } else {
                        mediaRepo.toggleAudioFavorite(item.mediaId);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _Scrubber(controller: controller, palette: palette),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.shuffle_rounded, color: playerState.shuffle ? palette.accent : palette.textMuted),
                    onPressed: controller.toggleShuffle,
                  ),
                  IconButton(
                    icon: Icon(Icons.skip_previous_rounded, color: palette.textPrimary, size: 32),
                    onPressed: playerState.hasPrevious ? controller.skipPrevious : null,
                  ),
                  Material(
                    color: palette.accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: controller.togglePlayPause,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Icon(playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white, size: 34),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.skip_next_rounded, color: palette.textPrimary, size: 32),
                    onPressed: playerState.hasNext ? controller.skipNext : null,
                  ),
                  IconButton(
                    icon: Icon(
                      playerState.repeat == RepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: playerState.repeat == RepeatMode.off ? palette.textMuted : palette.accent,
                    ),
                    onPressed: () {
                      final next = switch (playerState.repeat) {
                        RepeatMode.off => RepeatMode.all,
                        RepeatMode.all => RepeatMode.one,
                        RepeatMode.one => RepeatMode.off,
                      };
                      controller.setRepeatMode(next);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final speed = await showPlaybackSpeedSheet(context, playerState.speed);
                      if (speed != null) await controller.setSpeed(speed);
                    },
                    icon: const Icon(Icons.speed_rounded, size: 18),
                    label: Text('${playerState.speed}x'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.push(AppRoutes.equalizer),
                    icon: const Icon(Icons.equalizer_rounded, size: 18),
                    label: const Text('EQ'),
                  ),
                  TextButton.icon(
                    onPressed: () => showQueueSheet(context, ref),
                    icon: const Icon(Icons.queue_music_rounded, size: 18),
                    label: const Text('Queue'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreSheet(BuildContext context, WidgetRef ref, QueueItem item) {
    final controller = ref.read(globalPlayerControllerProvider.notifier);
    final mediaRepo = ref.read(mediaRepositoryProvider);
    final audio = mediaRepo.audioById(item.mediaId);
    final video = item.isVideo ? mediaRepo.videoById(item.mediaId) : null;

    showMediaBottomSheet(
      context: context,
      title: item.title,
      subtitle: item.artist ?? 'Audio options',
      actions: [
        SheetAction(
          icon: Icons.playlist_add_rounded,
          label: 'Add to playlist',
          onTap: () => showPlaylistPickerSheet(context: context, ref: ref, mediaRef: item.mediaRef),
        ),
        SheetAction(
          icon: Icons.volume_up_rounded,
          label: 'Volume booster',
          onTap: () => showVolumeBoosterSheet(context, ref),
        ),
        if (item.isVideo && video != null) ...[
          SheetAction(
            icon: Icons.movie_rounded,
            label: 'Return to video',
            onTap: () async {
              await controller.playAsVideo();
              if (context.mounted) context.pushReplacement(AppRoutes.videoPlayer);
            },
          ),
          SheetAction(
            icon: Icons.audiotrack_rounded,
            label: 'Save as Audio',
            // Shows its own progress dialog (percentage + progress bar) while
            // extracting, so it never just sits there looking frozen.
            onTap: () => showSaveAsAudioDialog(context, ref, video),
          ),
        ],
        SheetAction(
          icon: Icons.info_outline_rounded,
          label: 'File information',
          onTap: () => showFileInfoSheet(context: context, video: video, audio: audio),
        ),
      ],
    );
  }
}

/// Renders the Now Playing art area in whichever [VisualizerStyle] the user
/// picked via the app bar toggle.
class _VisualizerArt extends StatelessWidget {
  final VisualizerStyle style;
  final QueueItem item;
  final bool playing;
  final PrismPalette palette;

  const _VisualizerArt({required this.style, required this.item, required this.playing, required this.palette});

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case VisualizerStyle.rotatingDisk:
        return RotatingDiskVisualizer(
          playing: playing,
          artPath: item.artUri,
          isVideo: item.isVideo,
          palette: palette,
        );
      case VisualizerStyle.spectrum:
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 12))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaThumbnail(path: item.artUri, isVideo: item.isVideo, borderRadius: 24),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0), Colors.black.withOpacity(0.55)],
                    ),
                  ),
                  child: SpectrumBarsOverlay(playing: playing, color: palette.accent, secondary: palette.accentSecondary),
                ),
              ),
            ],
          ),
        );
      case VisualizerStyle.wave:
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 12))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaThumbnail(path: item.artUri, isVideo: item.isVideo, borderRadius: 24),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withOpacity(0), Colors.black.withOpacity(0.55)],
                    ),
                  ),
                  child: WaveformOverlay(playing: playing, color: Colors.white),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _Scrubber extends ConsumerWidget {
  final GlobalPlayerController controller;
  final PrismPalette palette;
  const _Scrubber({required this.controller, required this.palette});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Isolated so only this small widget rebuilds on the ~4x/sec position
    // ticks, instead of the whole Now Playing screen.
    final positionMs = ref.watch(globalPlayerControllerProvider.select((s) => s.position.inMilliseconds));
    final durationMs = ref.watch(globalPlayerControllerProvider.select((s) => s.duration.inMilliseconds));
    final duration = durationMs == 0 ? 1 : durationMs;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: positionMs.clamp(0, duration).toDouble(),
            min: 0,
            max: duration.toDouble(),
            activeColor: palette.accent,
            inactiveColor: palette.divider,
            onChanged: (v) => controller.seekTo(Duration(milliseconds: v.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(Formatters.duration(positionMs), style: TextStyle(color: palette.textMuted, fontSize: 12)),
              Text(Formatters.duration(durationMs), style: TextStyle(color: palette.textMuted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
