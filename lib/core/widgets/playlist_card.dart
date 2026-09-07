import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PlaylistCard extends StatelessWidget {
  final String name;
  final int itemCount;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  const PlaylistCard({
    super.key,
    required this.name,
    required this.itemCount,
    required this.onTap,
    this.icon = Icons.queue_music_rounded,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [palette.accent, palette.accentSecondary]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
                  Text('$itemCount items', style: TextStyle(color: palette.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (onMore != null) IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: onMore),
          ],
        ),
      ),
    );
  }
}
