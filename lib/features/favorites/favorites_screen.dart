import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_boxes.dart';
import '../../core/widgets/audio_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/video_card.dart';
import '../../models/audio_model.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(mediaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          Hive.box<VideoModel>(HiveBoxes.videos).listenable(),
          Hive.box<AudioModel>(HiveBoxes.audio).listenable(),
        ]),
        builder: (context, _) {
          final videos = repo.favoriteVideos;
          final songs = repo.favoriteAudio;
          if (videos.isEmpty && songs.isEmpty) {
            return const EmptyState(icon: Icons.favorite_border_rounded, title: 'No favorites yet',
                message: 'Tap the heart on any video or song to add it here.');
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              if (videos.isNotEmpty) ...[
                Text('Videos (${videos.length})', style: TextStyle(color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.82,
                  ),
                  itemCount: videos.length,
                  itemBuilder: (context, i) => VideoCard(
                    video: videos[i],
                    onTap: () async {
                      await ref.read(globalPlayerControllerProvider.notifier).playVideo(videos[i], queueVideos: videos, startIndex: i);
                      if (context.mounted) context.push(AppRoutes.videoPlayer);
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (songs.isNotEmpty) ...[
                Text('Songs (${songs.length})', style: TextStyle(color: Theme.of(context).hintColor, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (int i = 0; i < songs.length; i++)
                  AudioCard(
                    audio: songs[i],
                    onTap: () async {
                      await ref.read(globalPlayerControllerProvider.notifier).playAudio(songs[i], queueAudio: songs, startIndex: i);
                      if (context.mounted) context.push(AppRoutes.audioPlayer);
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
