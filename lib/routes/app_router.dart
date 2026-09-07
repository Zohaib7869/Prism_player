import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/audio/music_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/equalizer/equalizer_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/folders/folder_detail_screen.dart';
import '../features/folders/folders_screen.dart';
import '../features/home/home_screen.dart';
import '../features/player/audio_player_screen.dart';
import '../features/player/video_player_screen.dart';
import '../features/playlists/playlist_detail_screen.dart';
import '../features/playlists/playlists_screen.dart';
import '../features/safe_media/pin_screens.dart';
import '../features/safe_media/safe_media_screen.dart';
import '../features/scan/storage_scan_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/subpages/appearance_settings_screen.dart';
import '../features/settings/subpages/audio_settings_screen.dart';
import '../features/settings/subpages/library_settings_screen.dart';
import '../features/settings/subpages/playback_settings_screen.dart';
import '../features/settings/subpages/security_settings_screen.dart';
import '../features/settings/subpages/storage_settings_screen.dart';
import '../features/settings/subpages/video_settings_screen.dart';
import '../features/videos/videos_screen.dart';
import 'main_shell.dart';

/// Route path constants so no screen ever hard-codes a raw string when
/// navigating (see AppRoutes.push* helpers used throughout feature code).
class AppRoutes {
  AppRoutes._();
  static const home = '/';
  static const videos = '/videos';
  static const music = '/music';
  static const folders = '/folders';
  static const settings = '/settings';
  static const search = '/search';
  static const favorites = '/favorites';
  static const playlists = '/playlists';
  static const safeMedia = '/safe-media';
  static const equalizer = '/equalizer';
  static const scanStorage = '/scan-storage';
  static const downloads = '/downloads';
  static const videoPlayer = '/player/video';
  static const audioPlayer = '/player/audio';
}

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.home,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: AppRoutes.home, builder: (c, s) => const HomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: AppRoutes.videos, builder: (c, s) => const VideosScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: AppRoutes.music, builder: (c, s) => const MusicScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: AppRoutes.folders, builder: (c, s) => const FoldersScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: AppRoutes.settings, builder: (c, s) => const SettingsScreen()),
        ]),
      ],
    ),

    GoRoute(
      path: '${AppRoutes.folders}/detail',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => FolderDetailScreen(folderPath: s.extra as String),
    ),
    GoRoute(
      path: AppRoutes.search,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const SearchScreen(),
    ),
    GoRoute(
      path: AppRoutes.favorites,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const FavoritesScreen(),
    ),
    GoRoute(
      path: AppRoutes.playlists,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const PlaylistsScreen(),
    ),
    GoRoute(
      path: '${AppRoutes.playlists}/detail',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => PlaylistDetailScreen(playlistId: s.extra as String),
    ),
    GoRoute(
      path: AppRoutes.safeMedia,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const SafeMediaGate(),
    ),
    GoRoute(
      path: '${AppRoutes.safeMedia}/setup-pin',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const SetupPinScreen(),
    ),
    GoRoute(
      path: AppRoutes.equalizer,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const EqualizerScreen(),
    ),
    GoRoute(
      path: AppRoutes.scanStorage,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const StorageScanScreen(),
    ),
    GoRoute(
      path: AppRoutes.downloads,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const DownloadsScreen(),
    ),
    GoRoute(
      path: AppRoutes.videoPlayer,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const VideoPlayerScreen(),
    ),
    GoRoute(
      path: AppRoutes.audioPlayer,
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const AudioPlayerScreen(),
    ),

    GoRoute(
      path: '${AppRoutes.settings}/playback',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const PlaybackSettingsScreen(),
    ),
    GoRoute(
      path: '${AppRoutes.settings}/video',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const VideoSettingsScreen(),
    ),
    GoRoute(
      path: '${AppRoutes.settings}/audio',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const AudioSettingsScreen(),
    ),
    GoRoute(
      path: '${AppRoutes.settings}/library',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const LibrarySettingsScreen(),
    ),
    GoRoute(
      path: '${AppRoutes.settings}/appearance',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const AppearanceSettingsScreen(),
    ),
    GoRoute(
      path: '${AppRoutes.settings}/security',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const SecuritySettingsScreen(),
    ),
    GoRoute(
      path: '${AppRoutes.settings}/storage',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => const StorageSettingsScreen(),
    ),
  ],
);
