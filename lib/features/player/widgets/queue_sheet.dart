import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/media_thumbnail.dart';
import '../../../models/queue_item.dart';
import '../../../providers/app_providers.dart';

void showQueueSheet(BuildContext context, WidgetRef ref) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.surfaceElevated,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Consumer(
        builder: (context, ref, _) {
          final playerState = ref.watch(globalPlayerControllerProvider);
          final controller = ref.read(globalPlayerControllerProvider.notifier);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Up next (${playerState.queue.length})',
                    style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: playerState.queue.length,
                  itemBuilder: (context, i) {
                    final item = playerState.queue[i];
                    final isCurrent = i == playerState.currentIndex;
                    return ListTile(
                      leading: SizedBox(
                        width: 44, height: 44,
                        child: MediaThumbnail(path: item.artUri, isVideo: item.isVideo, borderRadius: 8),
                      ),
                      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isCurrent ? palette.accent : palette.textPrimary, fontWeight: FontWeight.w600)),
                      subtitle: Text(item.artist ?? Formatters.duration(item.durationMs),
                          style: TextStyle(color: palette.textMuted, fontSize: 12)),
                      trailing: isCurrent ? Icon(Icons.equalizer_rounded, color: palette.accent) : null,
                      onTap: () async {
                        if (i != playerState.currentIndex && playerState.mode == PlaybackMode.audio) {
                          // Route through the controller (not audioHandler
                          // directly) so state.currentIndex stays in sync —
                          // see playQueueIndex's doc comment for why this
                          // matters: it's what previously caused the title/
                          // thumbnail shown to not match the audio playing.
                          await controller.playQueueIndex(i);
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
