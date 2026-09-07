import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/audio_model.dart';
import '../../../models/video_model.dart';

void showFileInfoSheet({required BuildContext context, VideoModel? video, AudioModel? audio}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  final rows = <(String, String)>[];

  if (video != null) {
    rows.addAll([
      ('Filename', video.title),
      ('Path', video.path),
      ('Size', Formatters.fileSize(video.sizeBytes)),
      ('Duration', Formatters.duration(video.durationMs)),
      ('Resolution', Formatters.resolution(video.width, video.height)),
      ('Format', video.mimeType),
      ('Date modified', Formatters.relativeDate(video.dateModifiedMs)),
    ]);
  } else if (audio != null) {
    rows.addAll([
      ('Filename', audio.title),
      ('Path', audio.path),
      ('Artist', audio.artist),
      ('Album', audio.album),
      if (audio.genre != null) ('Genre', audio.genre!),
      ('Size', Formatters.fileSize(audio.sizeBytes)),
      ('Duration', Formatters.duration(audio.durationMs)),
      ('Format', audio.mimeType),
      ('Date modified', Formatters.relativeDate(audio.dateModifiedMs)),
    ]);
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: palette.surfaceElevated,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File information', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 100, child: Text(row.$1, style: TextStyle(color: palette.textMuted, fontSize: 13))),
                    Expanded(child: Text(row.$2, style: TextStyle(color: palette.textPrimary, fontSize: 13))),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
