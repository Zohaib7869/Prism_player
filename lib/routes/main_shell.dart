import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/services/global_player_controller.dart';
import '../core/widgets/mini_player.dart';
import '../models/queue_item.dart';
import '../providers/app_providers.dart';

/// Wraps every top-level tab (Home / Videos / Music / Folders / Settings)
/// with the bottom navigation bar and the persistent mini-player, which
/// floats above the nav bar and survives navigation between tabs — the
/// single global player never gets rebuilt or interrupted by tab switches.
class MainShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const MainShell({super.key, required this.navigationShell});

  static const _destinations = [
    (icon: Icons.home_rounded, outlineIcon: Icons.home_outlined, label: 'Home'),
    (icon: Icons.movie_rounded, outlineIcon: Icons.movie_outlined, label: 'Videos'),
    (icon: Icons.music_note_rounded, outlineIcon: Icons.music_note_outlined, label: 'Music'),
    (icon: Icons.folder_rounded, outlineIcon: Icons.folder_outlined, label: 'Folders'),
    (icon: Icons.settings_rounded, outlineIcon: Icons.settings_outlined, label: 'More'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only needs to know whether *something* is loaded, not position/duration
    // which tick ~4x/sec — this wraps every tab in the app, so watching the
    // whole state here would trigger unnecessary rebuilds app-wide on every
    // tick.
    final playerMode = ref.watch(globalPlayerControllerProvider.select((s) => s.mode));
    // The Videos tab has its own video-focused mini player context — an
    // audio-mode mini player (e.g. a song playing while the user is
    // browsing videos) is intentionally hidden there so it doesn't look
    // like it belongs to whatever video is on screen. It still shows on
    // every other tab.
    final onVideosTab = navigationShell.currentIndex == 1;
    final showMiniPlayer =
        playerMode != PlaybackMode.none && !(playerMode == PlaybackMode.audio && onVideosTab);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          if (showMiniPlayer)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                bottom: false,
                child: const MiniPlayer(),
              ),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        items: [
          for (final d in _destinations)
            BottomNavigationBarItem(
              icon: Icon(d.outlineIcon),
              activeIcon: Icon(d.icon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
