import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/audio_card.dart';
import '../../../models/audio_model.dart';
import '../../../providers/app_providers.dart';
import '../../../routes/app_router.dart';

class HomeAudioTile extends ConsumerWidget {
  final AudioModel audio;
  const HomeAudioTile({super.key, required this.audio});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AudioCard(
      audio: audio,
      onTap: () async {
        await ref.read(globalPlayerControllerProvider.notifier).playAudio(audio);
        if (context.mounted) context.push(AppRoutes.audioPlayer);
      },
    );
  }
}
