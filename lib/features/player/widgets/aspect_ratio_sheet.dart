import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const aspectRatioOptions = ['Fit', 'Fill', 'Crop', '16:9', '4:3', 'Original'];

Future<String?> showAspectRatioSheet(BuildContext context, String current) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: palette.surfaceElevated,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Aspect ratio', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          for (final option in aspectRatioOptions)
            RadioListTile<String>(
              value: option,
              groupValue: current,
              title: Text(option),
              activeColor: palette.accent,
              onChanged: (v) => Navigator.pop(context, v),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
