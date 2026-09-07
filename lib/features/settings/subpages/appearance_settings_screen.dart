import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';
import '../widgets/settings_tile.dart';

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        children: [
          SettingsSectionLabel('Theme'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
              children: [
                for (final type in AppThemeTypeX.selectable)
                  _ThemeSwatch(
                    type: type,
                    selected: themeState.type == type,
                    onTap: () => themeNotifier.setThemeType(type),
                  ),
              ],
            ),
          ),
          for (final group in AppThemeTypeX.wallpaperCategories) ...[
            SettingsSectionLabel(group.$1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.62,
                children: [
                  for (final type in group.$2)
                    _ThemeSwatch(
                      type: type,
                      selected: themeState.type == type,
                      onTap: () => themeNotifier.setThemeType(type),
                    ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _WallpaperTransparencySlider(
              value: themeState.wallpaperDim ?? themeState.palette.imageDim,
              onChanged: themeNotifier.setWallpaperDim,
            ),
          ),
          SettingsSectionLabel('Custom accent'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in const [Colors.red, Colors.orange, Colors.amber, Colors.green, Colors.teal, Colors.blue, Colors.indigo, Colors.pink])
                  GestureDetector(
                    onTap: () => themeNotifier.setCustomAccent(color),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: color,
                      child: (themeState.type == AppThemeType.custom && themeState.customAccent.value == color.value)
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          if (themeState.type == AppThemeType.custom)
            SettingsSwitchTile(
              title: 'Dark background',
              value: themeState.customIsDark,
              onChanged: (v) => themeNotifier.setCustomIsDark(v),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Lets the user control how visible a wallpaper-theme's background photo
/// is through the app's dark tint. Internally this drives [PrismPalette.imageDim]
/// (0 = no scrim, wallpaper fully visible; 1 = scrim fully opaque, wallpaper
/// hidden) — the slider itself is inverted so "more transparency" (dragging
/// right) reads naturally as "more of the photo shows through".
class _WallpaperTransparencySlider extends StatelessWidget {
  final double value; // this is imageDim (0..1)
  final ValueChanged<double> onChanged;
  const _WallpaperTransparencySlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final transparency = (1 - value).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.opacity_rounded, size: 18, color: palette.textMuted),
            const SizedBox(width: 8),
            Text('Wallpaper transparency', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('${(transparency * 100).round()}%', style: TextStyle(color: palette.textMuted, fontSize: 12)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: transparency,
            min: 0,
            max: 1,
            activeColor: palette.accent,
            inactiveColor: palette.divider,
            onChanged: (t) => onChanged(1 - t),
          ),
        ),
        Text(
          'Controls how much of the photo shows through on wallpaper themes.',
          style: TextStyle(color: palette.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final AppThemeType type;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeSwatch({required this.type, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = PrismThemes.paletteFor(type);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: palette.backgroundImage != null ? 116 : 60,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              // Wallpaper themes preview the real asset; flat themes preview
              // their gradient.
              image: palette.backgroundImage != null
                  ? DecorationImage(
                      image: AssetImage(palette.backgroundImage!),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withOpacity(palette.imageDim * 0.6),
                        BlendMode.darken,
                      ),
                    )
                  : null,
              gradient: palette.backgroundImage == null
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: palette.backgroundStops,
                    )
                  : null,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? palette.accent : palette.glassBorder,
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [palette.accent, palette.accentSecondary]),
                  boxShadow: [
                    BoxShadow(color: palette.accent.withOpacity(0.45), blurRadius: 12),
                  ],
                ),
                child: selected
                    ? Icon(Icons.check_rounded, size: 16, color: palette.isDark ? Colors.black : Colors.white)
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            type.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w400),
          ),
        ],
      ),
    );
  }
}
