import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/services/global_player_controller.dart';
import '../../core/services/youtube_service.dart';
import '../../core/utils/subtitle_parser.dart';
import '../../core/widgets/media_bottom_sheet.dart';
import '../../models/queue_item.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';
import 'widgets/aspect_ratio_sheet.dart';
import 'widgets/file_info_sheet.dart';
import 'widgets/gesture_osd.dart';
import 'widgets/player_controls_overlay.dart';
import 'widgets/playback_speed_sheet.dart';
import 'widgets/save_as_audio_dialog.dart';
import 'widgets/subtitle_overlay.dart';
import 'widgets/subtitle_settings_sheet.dart';
import 'widgets/video_gesture_layer.dart';
import 'widgets/volume_booster_sheet.dart';
import 'widgets/youtube_options_sheet.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  bool _controlsVisible = true;
  bool _locked = false;
  bool _fullscreen = false;
  // Guards the "bounce to audio player" navigation below so it only ever
  // fires once. Without this, every provider rebuild while mode==audio
  // (including the ~4x/sec position ticks) scheduled *another*
  // pushReplacement, which kept restarting the slide-in transition —
  // looking like the audio player was stuck looping mid-slide.
  bool _bouncedToAudio = false;
  String _aspectRatioMode = 'Fit';
  Timer? _hideControlsTimer;

  List<SubtitleCue> _cues = [];
  bool _subtitlesEnabled = true;
  String? _lastLoadedSubtitleForPath;

  // YouTube-only extras: available caption languages/qualities for the item
  // currently playing, and which ones are active. Populated by
  // _tryLoadSubtitles (captions list) and fetched on demand for qualities
  // (see _showMoreSheet) since the manifest is already cached by then.
  List<YoutubeCaptionTrack> _ccTracks = [];
  String? _ccLanguageCode;
  String? _currentQualityLabel;

  double? _brightnessOsd;
  double? _volumeOsd;
  double? _brightnessCache;
  double? _volumeCache;
  Duration? _seekOsd;
  Timer? _osdHideTimer;
  Duration _dragAccumulated = Duration.zero;
  Duration _dragBasePosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _aspectRatioMode = ref.read(settingsRepositoryProvider).defaultAspectRatio;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoadSubtitles());
    _scheduleAutoHide();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _hideControlsTimer?.cancel();
    _osdHideTimer?.cancel();
    _restoreSystemUi();
    super.dispose();
  }

  void _restoreSystemUi() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _scheduleAutoHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  Future<void> _tryLoadSubtitles() async {
    final playerState = ref.read(globalPlayerControllerProvider);
    final item = playerState.current;
    if (item == null || !item.isVideo || item.path == _lastLoadedSubtitleForPath) return;
    _lastLoadedSubtitleForPath = item.path;

    if (item.isYoutube) {
      // Reset per-video YouTube state (new video, new manifest) and fetch
      // just the list of available languages — the actual cue text is only
      // downloaded once the user picks one from the CC sheet, so opening a
      // video someone never turns captions on for costs nothing extra.
      if (mounted) setState(() { _cues = []; _ccTracks = []; _ccLanguageCode = null; _currentQualityLabel = null; });
      final ytService = ref.read(youtubeServiceProvider);
      // Warm the quality ladder in the background as soon as the video loads,
      // so tapping "Quality" later just reads the cache instead of paying for
      // _upgradeToRichestManifest (3 concurrent client fetches) at tap time.
      unawaited(ytService.getQualityOptions(item.mediaId));
      final tracks = await ytService.getCaptionTracks(item.mediaId);
      if (mounted) setState(() => _ccTracks = tracks);
      return;
    }

    final dir = Directory(item.path).parent;
    final baseName = item.path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      final matchesBase = name.startsWith(baseName);
      final ext = name.split('.').last.toLowerCase();
      if (matchesBase && ['srt', 'vtt', 'ass', 'ssa'].contains(ext)) {
        try {
          final content = await entity.readAsString();
          final cues = SubtitleParser.parse(content, ext);
          if (mounted) setState(() => _cues = cues);
        } catch (_) {
          // Unreadable/corrupt subtitle file — silently skip rather than crash playback.
        }
        break;
      }
    }
  }

  void _showOsdBrightness(double value) {
    setState(() => _brightnessOsd = value);
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _brightnessOsd = null);
    });
  }

  void _showOsdVolume(double value) {
    setState(() => _volumeOsd = value);
    _osdHideTimer?.cancel();
    _osdHideTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _volumeOsd = null);
    });
  }

  // NOTE: screen_brightness's exact API (ScreenBrightness().current /
  // .setScreenBrightness()) is written from memory — this sandbox has no
  // network access to pub.dev to confirm it against whatever version
  // `flutter pub get` resolves. Double-check against the installed version's
  // docs if this doesn't compile as-is; see README "Unverified build" note.
  //
  // _brightnessCache/_volumeCache hold the last known value locally instead
  // of re-reading it from the OS on every drag event. onVerticalDragUpdate
  // fires many times per second and each handler call is async — re-reading
  // "current" from the OS on every single event races against the previous
  // event's still-in-flight "set": whichever set() happens to land last
  // wins, regardless of which drag event it came from, so a steady one-
  // direction swipe could visibly bounce up/down instead of moving
  // smoothly. Keeping one local double as the source of truth during the
  // gesture removes the race entirely — every event reads and writes it
  // synchronously, and the OS call becomes fire-and-forget.
  Future<void> _onBrightnessDelta(double fraction) async {
    try {
      _brightnessCache ??= await ScreenBrightness().current;
      final next = (_brightnessCache! + fraction).clamp(0.0, 1.0);
      _brightnessCache = next;
      _showOsdBrightness(next);
      unawaited(ScreenBrightness().setScreenBrightness(next));
    } catch (_) {
      // Some devices/emulators don't support programmatic brightness control.
    }
  }

  // volume_controller's current API is a singleton (`VolumeController.instance`)
  // with async getVolume()/setVolume() methods. See _brightnessCache's doc
  // comment above — same local-cache fix applies here.
  Future<void> _onVolumeDelta(double fraction) async {
    try {
      _volumeCache ??= await VolumeController.instance.getVolume();
      final next = (_volumeCache! + fraction).clamp(0.0, 1.0);
      _volumeCache = next;
      _showOsdVolume(next);
      unawaited(VolumeController.instance.setVolume(next));
    } catch (_) {
      // Defensive — keep the gesture responsive even if the platform call fails.
    }
  }

  void _onSeekPreviewStart(PlayerUiState state) {
    _dragBasePosition = state.position;
    _dragAccumulated = Duration.zero;
  }

  void _onSeekPreview(double fraction, Duration duration) {
    final deltaMs = (fraction * duration.inMilliseconds * 0.8).round();
    _dragAccumulated += Duration(milliseconds: deltaMs);
    final target = _dragBasePosition + _dragAccumulated;
    final clamped = target < Duration.zero ? Duration.zero : (target > duration ? duration : target);
    setState(() => _seekOsd = clamped);
  }

  Future<void> _onSeekEnd() async {
    if (_seekOsd == null) return;
    await ref.read(globalPlayerControllerProvider.notifier).seekTo(_seekOsd!);
    setState(() => _seekOsd = null);
  }

  Future<void> _pickSubtitleFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final ext = path.split('.').last.toLowerCase();
    try {
      final content = await File(path).readAsString();
      final cues = SubtitleParser.parse(content, ext);
      if (mounted) setState(() {
        _cues = cues;
        _subtitlesEnabled = true;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read that subtitle file')));
      }
    }
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  /// Shown while a remote (YouTube) stream is still being resolved. The
  /// screen is now pushed the instant the user taps a search result, so this
  /// is the first thing they see — a dimmed thumbnail with the title reads as
  /// "your video is opening" rather than as a frozen black screen.
  Widget _buildConnecting(QueueItem item) {
    final thumb = item.artUri;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null && thumb.startsWith('http'))
            Opacity(
              opacity: 0.35,
              child: Image.network(
                thumb,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    item.title,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () {
                  ref.read(globalPlayerControllerProvider.notifier).stopAndClear();
                  if (context.canPop()) context.pop();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(globalPlayerControllerProvider);
    final controller = ref.read(globalPlayerControllerProvider.notifier);
    final videoController = playerState.videoController;
    final mkController = playerState.mkVideoController;
    final item = playerState.current;
    final settings = ref.read(settingsRepositoryProvider);

    if (playerState.mode != PlaybackMode.video || item == null) {
      // We got here while switching to audio mode (Play as Audio) — bounce to
      // the audio player, but only once: this branch's build() can re-run
      // many times while state.mode == audio (video controller now null, so
      // this whole condition stays true; plus the position ticker keeps
      // ticking during that window), and without a guard each rebuild used
      // to schedule its own pushReplacement, repeatedly restarting the
      // slide-in transition.
      if (!_bouncedToAudio) {
        _bouncedToAudio = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (playerState.mode == PlaybackMode.audio) {
            context.pushReplacement('/player/audio');
          } else if (playerState.mode == PlaybackMode.none) {
            // Guard: this screen can be the first route (deep link / restart),
            // where pop() throws "There is nothing to pop".
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          } else {
            // Neither audio nor none (e.g. still mid-switch) — allow a retry.
            _bouncedToAudio = false;
          }
        });
      }
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    if (videoController == null && mkController == null) {
      // Still connecting (this screen is now pushed immediately for remote
      // YouTube streams, before the network round trip finishes) — or the
      // connect failed. Either way, stay on this screen instead of bouncing
      // away, and actually show the error instead of spinning forever.
      if (playerState.errorMessage != null) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playerState.errorMessage!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      controller.stopAndClear();
                      context.pop();
                    },
                    child: const Text('Go back'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return _buildConnecting(item);
    }

    return PopScope(
      // Leaving the video screen no longer stops playback: the video keeps
      // running inside the floating mini player (YouTube-style), which owns
      // play/pause, next/prev, expand-to-fullscreen and an explicit close.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_fullscreen) {
          _toggleFullscreen();
          return;
        }
        _restoreSystemUi();
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => setState(() {
            _controlsVisible = !_controlsVisible;
            if (_controlsVisible) _scheduleAutoHide();
          }),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(child: _buildVideoSurface(videoController, mkController)),
              if (playerState.errorMessage != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(playerState.errorMessage!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  ),
                ),
              if (_subtitlesEnabled)
                SubtitleOverlay(
                  cues: _cues,
                  position: playerState.position,
                  delayMs: settings.subtitleDelayMs,
                  fontSize: settings.subtitleSize,
                  color: Color(settings.subtitleColor),
                  background: settings.subtitleBackground,
                ),
              VideoGestureLayer(
                enabled: settings.gestureControlsEnabled,
                locked: _locked,
                doubleTapSeekSeconds: settings.doubleTapSeekSeconds,
                onBrightnessDelta: _onBrightnessDelta,
                onVolumeDelta: _onVolumeDelta,
                onSeekPreview: (f) {
                  if (_seekOsd == null) _onSeekPreviewStart(playerState);
                  _onSeekPreview(f, playerState.duration);
                },
                onSeekEnd: _onSeekEnd,
                onDoubleTapRewind: () => controller.seekRelative(Duration(seconds: -settings.doubleTapSeekSeconds)),
                onDoubleTapForward: () => controller.seekRelative(Duration(seconds: settings.doubleTapSeekSeconds)),
                onDoubleTapPlayPause: controller.togglePlayPause,
                onSingleTap: () => setState(() {
                  _controlsVisible = !_controlsVisible;
                  if (_controlsVisible) _scheduleAutoHide();
                }),
                child: const SizedBox.expand(),
              ),
              GestureOsd(brightness: _brightnessOsd, volume: _volumeOsd, seekPosition: _seekOsd, totalDuration: playerState.duration),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: PlayerControlsOverlay(
                    title: item.title,
                    isPlaying: playerState.isPlaying,
                    isBuffering: playerState.isBuffering,
                    locked: _locked,
                    position: playerState.position,
                    duration: playerState.duration,
                    hasNext: playerState.hasNext,
                    hasPrevious: playerState.hasPrevious,
                    onBack: () => _fullscreen ? _toggleFullscreen() : context.pop(),
                    onPlayPause: controller.togglePlayPause,
                    onSkipNext: controller.skipNext,
                    onSkipPrevious: controller.skipPrevious,
                    onSeek: controller.seekTo,
                    onLockToggle: () => setState(() => _locked = !_locked),
                    onMore: () => _showMoreSheet(context, item, playerState),
                    onPlayAsAudio: controller.playAsAudio,
                    onFullscreenToggle: _toggleFullscreen,
                    isFullscreen: _fullscreen,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSurface(VideoPlayerController? videoController, mkv.VideoController? mkController) {
    if (mkController != null) {
      // Remote (YouTube) item — media_kit's own fit handles aspect ratio,
      // no need to read a native size/aspectRatio value up front like the
      // video_player path below does.
      final fit = switch (_aspectRatioMode) {
        'Fill' => BoxFit.fill,
        'Crop' => BoxFit.cover,
        '16:9' => BoxFit.contain,
        '4:3' => BoxFit.contain,
        _ => BoxFit.contain,
      };
      return mkv.Video(controller: mkController, fit: fit, controls: mkv.NoVideoControls);
    }

    final videoControllerNonNull = videoController!;
    final size = videoControllerNonNull.value.size;
    final nativeAspect =
        videoControllerNonNull.value.aspectRatio == 0 ? 16 / 9 : videoControllerNonNull.value.aspectRatio;

    switch (_aspectRatioMode) {
      case 'Fill':
      case 'Crop':
        return SizedBox.expand(
          child: FittedBox(
            fit: _aspectRatioMode == 'Fill' ? BoxFit.fill : BoxFit.cover,
            child: SizedBox(width: size.width == 0 ? 16 : size.width, height: size.height == 0 ? 9 : size.height,
                child: VideoPlayer(videoControllerNonNull)),
          ),
        );
      case '16:9':
        return AspectRatio(aspectRatio: 16 / 9, child: VideoPlayer(videoControllerNonNull));
      case '4:3':
        return AspectRatio(aspectRatio: 4 / 3, child: VideoPlayer(videoControllerNonNull));
      case 'Fit':
      case 'Original':
      default:
        return AspectRatio(aspectRatio: nativeAspect, child: VideoPlayer(videoControllerNonNull));
    }
  }

  void _showMoreSheet(BuildContext context, QueueItem item, PlayerUiState playerState) {
    final controller = ref.read(globalPlayerControllerProvider.notifier);
    final mediaRepo = ref.read(mediaRepositoryProvider);
    final video = mediaRepo.videoById(item.mediaId);

    showMediaBottomSheet(
      context: context,
      title: item.title,
      subtitle: 'Video options',
      actions: [
        SheetAction(
          icon: Icons.speed_rounded,
          label: 'Playback speed (${playerState.speed}x)',
          onTap: () async {
            final speed = await showPlaybackSpeedSheet(context, playerState.speed);
            if (speed != null) await controller.setSpeed(speed);
          },
        ),
        SheetAction(
          icon: Icons.aspect_ratio_rounded,
          label: 'Aspect ratio ($_aspectRatioMode)',
          onTap: () async {
            final mode = await showAspectRatioSheet(context, _aspectRatioMode);
            if (mode != null) setState(() => _aspectRatioMode = mode);
          },
        ),
        if (item.isYoutube) ...[
          SheetAction(
            icon: Icons.high_quality_rounded,
            label: _currentQualityLabel == null ? 'Quality' : 'Quality: $_currentQualityLabel',
            onTap: () async {
              final ytService = ref.read(youtubeServiceProvider);
              final options = await ytService.getQualityOptions(item.mediaId);
              if (!context.mounted) return;
              final chosen = await showQualitySheet(context, options, _currentQualityLabel);
              if (chosen == null) return;
              await controller.switchRemoteQuality(chosen.url, audioUrl: chosen.audioUrl);
              if (mounted) setState(() => _currentQualityLabel = chosen.label);
            },
          ),
          SheetAction(
            icon: _cues.isNotEmpty && _subtitlesEnabled ? Icons.closed_caption_rounded : Icons.closed_caption_off_rounded,
            label: _ccLanguageCode == null
                ? 'Subtitles/CC'
                : 'CC: ${_ccTracks.firstWhere((t) => t.languageCode == _ccLanguageCode, orElse: () => _ccTracks.first).languageName}',
            onTap: () async {
              final chosen = await showCaptionLanguageSheet(context, _ccTracks, _ccLanguageCode);
              if (chosen == null) return;
              if (chosen.isOff) {
                setState(() { _ccLanguageCode = null; _cues = []; });
                return;
              }
              final cues = await ref.read(youtubeServiceProvider).getCaptionCues(item.mediaId, chosen.languageCode!);
              if (mounted) {
                setState(() {
                  _ccLanguageCode = chosen.languageCode;
                  _cues = cues;
                  _subtitlesEnabled = true;
                });
              }
            },
          ),
          SheetAction(
            icon: Icons.tune_rounded,
            label: 'Subtitle settings',
            onTap: () => showSubtitleSettingsSheet(context, ref, () => setState(() {})),
          ),
        ] else ...[
          SheetAction(
            icon: _subtitlesEnabled ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
            label: _cues.isEmpty ? 'No subtitles found for this video' : (_subtitlesEnabled ? 'Subtitles: On' : 'Subtitles: Off'),
            onTap: () => setState(() => _subtitlesEnabled = !_subtitlesEnabled),
          ),
          SheetAction(
            icon: Icons.tune_rounded,
            label: 'Subtitle settings',
            onTap: () => showSubtitleSettingsSheet(context, ref, () => setState(() {})),
          ),
          SheetAction(
            icon: Icons.folder_open_rounded,
            label: 'Load subtitle file…',
            onTap: _pickSubtitleFile,
          ),
        ],
        SheetAction(
          icon: Icons.audiotrack_rounded,
          label: 'Audio track',
          onTap: () => showDialog(
            context: context,
            builder: (context) => const AlertDialog(
              title: Text('Audio track'),
              content: Text(
                'This video is using its default audio track. Switching between multiple embedded '
                'audio tracks needs deeper native ExoPlayer track-selection support than this build '
                'includes yet — see the README for details.',
              ),
            ),
          ),
        ),
        SheetAction(
          icon: Icons.volume_up_rounded,
          label: 'Volume booster',
          onTap: () => showVolumeBoosterSheet(context, ref),
        ),
        SheetAction(
          icon: Icons.graphic_eq_rounded,
          label: 'Equalizer',
          // Native video playback has no Android audio session for effects
          // to attach to (see EqualizerService), so band/bass/virtualizer
          // changes made here won't be audible until this video is switched
          // to "Play as Audio" or the item plays from Music instead. The
          // screen itself explains this; we still expose the entry point
          // here so users aren't left wondering where the EQ went.
          onTap: () => context.push(AppRoutes.equalizer),
        ),
        SheetAction(
          icon: Icons.headphones_rounded,
          label: 'Play as Audio',
          // No manual navigation here — VideoPlayerScreen's own build()
          // detects mode switching to audio and bounces to the audio player
          // exactly once (see _bouncedToAudio). Doing it here too raced with
          // that and could double-navigate.
          onTap: () => controller.playAsAudio(),
        ),
        if (video != null)
          SheetAction(
            icon: Icons.audio_file_rounded,
            label: 'Save as Audio',
            onTap: () => showSaveAsAudioDialog(context, ref, video),
          ),
        SheetAction(
          icon: Icons.screen_rotation_rounded,
          label: 'Rotate screen',
          onTap: _toggleFullscreen,
        ),
        if (video != null)
          SheetAction(
            icon: Icons.info_outline_rounded,
            label: 'File information',
            onTap: () => showFileInfoSheet(context: context, video: video),
          ),
        SheetAction(
          icon: Icons.share_rounded,
          label: 'Share',
          onTap: () => Share.shareXFiles([XFile(item.path)], text: item.title),
        ),
      ],
    );
  }
}
