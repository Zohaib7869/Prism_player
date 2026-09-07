import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';

import 'core/constants/app_constants.dart';
import 'core/database/hive_boxes.dart';
import 'core/permissions/permission_service.dart';
import 'core/services/audio_playback_handler.dart';
import 'core/services/youtube_format_selector.dart';
import 'core/services/youtube_native_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/prism_background.dart';
import 'core/theme/theme_provider.dart';
import 'providers/app_providers.dart';
import 'routes/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Spike/step verification for the yt-dlp-android migration. This used to
  // run inline and awaited, *before* runApp — four native Chaquopy calls,
  // two of which do real network extraction, so every cold start paid for
  // them (and in release they were failing anyway, because yt-dlp's Python
  // init had not finished by the time the channel was invoked). It is now
  // debug-only and fire-and-forget, so it can never delay first frame.
  if (kDebugMode) {
    unawaited(_runYtDlpDiagnostics());
  }

  // Required once before any Player()/VideoController is created — this
  // spins up libmpv, used only for remote (YouTube) adaptive playback so
  // 720p/1080p video-only + audio-only streams can be played back merged.
  // Local file playback still goes through video_player/ExoPlayer, untouched.
  MediaKit.ensureInitialized();

  await AppDatabase.init();

  // Configures how playback behaves around phone calls, other apps requesting
  // audio focus, and headphones being unplugged (auto-pause), independent of
  // the audio_service notification/media-session wiring below.
  final audioSession = await AudioSession.instance;
  await audioSession.configure(const AudioSessionConfiguration.music());

  // audio_service must be initialized exactly once, before runApp, so the
  // Android foreground service + notification are ready the moment the app
  // first plays audio (Music, or a video switched to "Play as Audio"). That
  // also means its config (including notification color) is locked in at
  // this point — read whatever theme/accent the user last picked straight
  // out of Hive (already open from AppDatabase.init() above) so the
  // notification's mini player matches the in-app theme from the very first
  // notification, instead of falling back to Android's default gray.
  final audioHandler = await AudioService.init(
    builder: () => AudioPlaybackHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.prismplayer.app.audio',
      androidNotificationChannelName: 'Prism Player playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      notificationColor: _loadNotificationAccentColor(),
    ),
  );

  // Ask for media + notification permissions up front with a plain-language
  // rationale dialog shown by PermissionRequestGate on first frame, rather
  // than surprising the user — see that widget for the actual UI.

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const PrismPlayerApp(),
    ),
  );
}

/// Debug-only sanity checks for the native yt-dlp bridge. Deliberately not
/// awaited by [main] — it runs alongside the first frames instead of ahead of
/// them. Delete once step 5 lands.
Future<void> _runYtDlpDiagnostics() async {
  // Give Chaquopy's Python runtime a moment to finish initialising; calling
  // straight into the channel from main() is what produced
  // "YtDlp.init() has not completed successfully".
  await Future<void>.delayed(const Duration(seconds: 3));

  final ytdlp = YoutubeNativeService();
  try {
    debugPrint('ytdlp available: ${await ytdlp.isAvailable()}');
    debugPrint('ytdlp version: ${await ytdlp.getVersion()}');
  } catch (e) {
    debugPrint('ytdlp version error: $e');
  }
  try {
    // "Me at the zoo" (jNQXAC9IVRw) — YouTube's first-ever upload, chosen as
    // a stable, unlikely-to-disappear test video.
    final info = await ytdlp.getInfo('https://www.youtube.com/watch?v=jNQXAC9IVRw');
    debugPrint('ytdlp get_info: $info');
    debugPrint('ytdlp quality labels: ${YoutubeFormatSelector.availableQualityLabels(info.formats)}');
  } catch (e) {
    debugPrint('ytdlp get_info error: $e');
  }
}

/// Mirrors [ThemeNotifier]'s persisted-theme loading logic, but standalone —
/// this runs before runApp/ProviderScope exist, so it can't just read
/// [themeProvider]. Falls back to the same defaults ThemeNotifier uses if
/// nothing has been saved yet (fresh install).
Color _loadNotificationAccentColor() {
  final box = Hive.box(HiveBoxes.appSettings);
  final typeIndex = box.get(AppConstants.keyThemeType, defaultValue: 0) as int;
  final accentValue =
      box.get(AppConstants.keyCustomAccent, defaultValue: PrismThemes.midnight.accent.value) as int;
  final isDark = box.get(AppConstants.keyCustomIsDark, defaultValue: true) as bool;
  final type = AppThemeType.values[typeIndex.clamp(0, AppThemeType.values.length - 1)];
  final palette = PrismThemes.paletteFor(type, customAccent: Color(accentValue), customIsDark: isDark);
  return palette.accent;
}

class PrismPlayerApp extends ConsumerWidget {
  const PrismPlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Prism Player',
      debugShowCheckedModeBanner: false,
      theme: themeState.themeData,
      darkTheme: themeState.themeData,
      routerConfig: appRouter,
      // PrismBackground paints the shared gradient + glow backdrop once for the
      // whole app (Scaffolds are transparent), so every route gets it for free.
      builder: (context, child) => PrismBackground(
        child: PermissionRequestGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Requests media-library + notification permissions once on first launch,
/// then — and only then — kicks off the initial media scan. Screens (like
/// HomeScreen) just read from the repository/Hive boxes reactively; they no
/// longer trigger their own startup scan, which used to race the permission
/// dialog and silently scan with zero permissions before the user had even
/// tapped "Allow". If permission is denied, screens show their own
/// empty/error states rather than crashing.
class PermissionRequestGate extends ConsumerStatefulWidget {
  final Widget child;
  const PermissionRequestGate({super.key, required this.child});

  @override
  ConsumerState<PermissionRequestGate> createState() => _PermissionRequestGateState();
}

class _PermissionRequestGateState extends ConsumerState<PermissionRequestGate> {
  final _permissionService = PermissionService();
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissionsThenScan());
    }
  }

  Future<void> _requestPermissionsThenScan() async {
    var hasMedia = await _permissionService.hasMediaPermissions();
    if (!hasMedia) {
      hasMedia = await _permissionService.requestMediaPermissions();
    }
    await _permissionService.requestNotificationPermission();

    if (hasMedia) {
      // Safe to fire-and-forget: HomeScreen listens to the Hive boxes and
      // rebuilds automatically as soon as rows land, no matter how long the
      // scan takes.
      unawaited(ref.read(mediaRepositoryProvider).scan());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
