import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const SectionHeader({super.key, required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(color: palette.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: Text('See all', style: TextStyle(color: palette.accent))),
        ],
      ),
    );
  }
}
