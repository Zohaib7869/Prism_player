import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../routes/app_router.dart';

class QuickActionGrid extends StatelessWidget {
  QuickActionGrid({super.key});

  final _actions = const [
    (icon: Icons.movie_rounded, label: 'Videos', route: AppRoutes.videos),
    (icon: Icons.music_note_rounded, label: 'Music', route: AppRoutes.music),
    (icon: Icons.folder_rounded, label: 'Folders', route: AppRoutes.folders),
    (icon: Icons.lock_rounded, label: 'Safe', route: AppRoutes.safeMedia),
    (icon: Icons.queue_music_rounded, label: 'Playlists', route: AppRoutes.playlists),
    (icon: Icons.equalizer_rounded, label: 'Equalizer', route: AppRoutes.equalizer),
    (icon: Icons.travel_explore_rounded, label: 'Scan Storage', route: AppRoutes.scanStorage),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.5,
        ),
        itemCount: _actions.length,
        itemBuilder: (context, i) {
          final a = _actions[i];
          return InkWell(
            onTap: () => context.push(a.route),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(a.icon, color: palette.accent, size: 26),
                  const SizedBox(height: 6),
                  Text(a.label, style: TextStyle(color: palette.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
