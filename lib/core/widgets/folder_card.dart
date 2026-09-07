import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../models/folder_summary.dart';
import '../theme/app_theme.dart';
import 'media_thumbnail.dart';

class FolderCard extends StatelessWidget {
  final FolderSummary folder;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  const FolderCard({super.key, required this.folder, required this.onTap, this.onMore});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return InkWell(
      onTap: onTap,
      onLongPress: onMore,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: palette.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Icon(
                folder.type == FolderMediaType.audio ? Icons.folder_special_rounded : Icons.folder_rounded,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${folder.totalCount} items · ${Formatters.fileSize(folder.totalSizeBytes)}',
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
