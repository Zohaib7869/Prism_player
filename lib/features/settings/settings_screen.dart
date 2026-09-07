import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../routes/app_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final sections = [
      (icon: Icons.play_circle_outline_rounded, title: 'Playback', subtitle: 'Speed, auto-play, gestures', path: '${AppRoutes.settings}/playback'),
      (icon: Icons.movie_outlined, title: 'Video', subtitle: 'Aspect ratio, subtitles, hardware decode', path: '${AppRoutes.settings}/video'),
      (icon: Icons.graphic_eq_rounded, title: 'Audio', subtitle: 'Equalizer, volume booster, gapless', path: '${AppRoutes.settings}/audio'),
      (icon: Icons.video_library_outlined, title: 'Library', subtitle: 'Scan, excluded folders, sort order', path: '${AppRoutes.settings}/library'),
      (icon: Icons.palette_outlined, title: 'Appearance', subtitle: 'Theme, accent color, dark mode', path: '${AppRoutes.settings}/appearance'),
      (icon: Icons.security_rounded, title: 'Security', subtitle: 'Safe Media PIN, biometric unlock', path: '${AppRoutes.settings}/security'),
      (icon: Icons.storage_rounded, title: 'Storage', subtitle: 'Cache, media scan, storage info', path: '${AppRoutes.settings}/storage'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final s in sections)
            ListTile(
              leading: CircleAvatar(backgroundColor: palette.surface, child: Icon(s.icon, color: palette.accent)),
              title: Text(s.title, style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(s.subtitle, style: TextStyle(color: palette.textMuted, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push(s.path),
            ),
          const Divider(height: 32),
          const _AboutTile(),
        ],
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return ListTile(
      leading: CircleAvatar(backgroundColor: palette.surface, child: Icon(Icons.info_outline_rounded, color: palette.accent)),
      title: const Text('About Prism Player'),
      subtitle: const Text('Version, privacy, licenses'),
      onTap: () => showAboutDialog(
        context: context,
        applicationName: 'Prism Player',
        applicationVersion: '1.0.0',
        applicationIcon: Icon(Icons.play_circle_fill_rounded, color: palette.accent, size: 40),
        children: const [
          Text('A premium offline video and audio player built with Flutter.'),
        ],
      ),
    );
  }
}
