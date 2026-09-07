import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/global_player_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/queue_item.dart';
import '../../../providers/app_providers.dart';

void showVolumeBoosterSheet(BuildContext context, WidgetRef ref) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  showModalBottomSheet(
    context: context,
    backgroundColor: palette.surfaceElevated,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => const _VolumeBoosterSheetBody(),
  );
}

class _VolumeBoosterSheetBody extends ConsumerWidget {
  const _VolumeBoosterSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final playerState = ref.watch(globalPlayerControllerProvider);
    final controller = ref.read(globalPlayerControllerProvider.notifier);
    final percent = playerState.volumeBoostPercent;
    final appliesNow = playerState.mode == PlaybackMode.audio;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.volume_up_rounded, color: palette.accent),
                const SizedBox(width: 10),
                Text('Volume Booster', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
                const Spacer(),
                Text('$percent%', style: TextStyle(color: palette.accent, fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            if (!appliesNow)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(
                  'Applies to audio playback. Switch to "Play as Audio" or play a song to hear the boost.',
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ),
            Slider(
              value: percent.toDouble(),
              min: 100,
              max: 200,
              divisions: 20,
              label: '$percent%',
              activeColor: palette.accent,
              onChanged: (v) => controller.setVolumeBoostPercent(v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('100%', style: TextStyle(color: palette.textMuted, fontSize: 12)),
                Text('200%', style: TextStyle(color: palette.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => controller.setVolumeBoostPercent(100),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset to 100%'),
            ),
          ],
        ),
      ),
    );
  }
}
