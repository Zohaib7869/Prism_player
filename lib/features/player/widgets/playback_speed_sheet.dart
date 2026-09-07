import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';

Future<double?> showPlaybackSpeedSheet(BuildContext context, double current) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showModalBottomSheet<double>(
    context: context,
    backgroundColor: palette.surfaceElevated,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Playback speed', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          for (final speed in AppConstants.playbackSpeeds)
            RadioListTile<double>(
              value: speed,
              groupValue: current,
              title: Text(speed == 1.0 ? 'Normal (1x)' : '${speed}x'),
              activeColor: palette.accent,
              onChanged: (v) => Navigator.pop(context, v),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
