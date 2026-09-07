import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/app_providers.dart';

const List<Color> subtitleColorOptions = [
  Colors.white, Colors.yellow, Colors.cyanAccent, Colors.greenAccent, Colors.pinkAccent,
];

void showSubtitleSettingsSheet(BuildContext context, WidgetRef ref, VoidCallback onChanged) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  final settings = ref.read(settingsRepositoryProvider);
  showModalBottomSheet(
    context: context,
    backgroundColor: palette.surfaceElevated,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Subtitle settings', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              Text('Size', style: TextStyle(color: palette.textMuted, fontSize: 12)),
              Slider(
                value: settings.subtitleSize,
                min: 12,
                max: 32,
                activeColor: palette.accent,
                onChanged: (v) {
                  settings.subtitleSize = v;
                  setSheetState(() {});
                  onChanged();
                },
              ),
              Text('Color', style: TextStyle(color: palette.textMuted, fontSize: 12)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final color in subtitleColorOptions)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () {
                          settings.subtitleColor = color.value;
                          setSheetState(() {});
                          onChanged();
                        },
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: color,
                          child: settings.subtitleColor == color.value
                              ? const Icon(Icons.check, size: 16, color: Colors.black)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Background'),
                value: settings.subtitleBackground,
                activeColor: palette.accent,
                onChanged: (v) {
                  settings.subtitleBackground = v;
                  setSheetState(() {});
                  onChanged();
                },
              ),
              Text('Delay: ${settings.subtitleDelayMs} ms', style: TextStyle(color: palette.textMuted, fontSize: 12)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: () {
                      settings.subtitleDelayMs -= 100;
                      setSheetState(() {});
                      onChanged();
                    },
                  ),
                  Text('${settings.subtitleDelayMs} ms'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () {
                      settings.subtitleDelayMs += 100;
                      setSheetState(() {});
                      onChanged();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
