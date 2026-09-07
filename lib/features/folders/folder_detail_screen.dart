import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;

import '../../core/database/hive_boxes.dart';
import '../../core/widgets/audio_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/video_card.dart';
import '../../models/audio_model.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';

class FolderDetailScreen extends ConsumerStatefulWidget {
  final String folderPath;
  const FolderDetailScreen({super.key, required this.folderPath});

  @override
  ConsumerState<FolderDetailScreen> createState() => _FolderDetailScreenState();
}

class _FolderDetailScreenState extends ConsumerState<FolderDetailScreen> {
  bool _grid = true;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(mediaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.basename(widget.folderPath)),
        actions: [
          IconButton(
            icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
            onPressed: () => setState(() => _grid = !_grid),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          Hive.box<VideoModel>(HiveBoxes.videos).listenable(),
          Hive.box<AudioModel>(HiveBoxes.audio).listenable(),
        ]),
        builder: (context, _) {
          final videos = repo.videosInFolder(widget.folderPath);
          final audio = repo.audioInFolder(widget.folderPath);
          if (videos.isEmpty && audio.isEmpty) {
            return const EmptyState(icon: Icons.folder_open_rounded, title: 'This folder is empty');
          }
          return CustomScrollView(
            slivers: [
              if (videos.isNotEmpty)
                _grid
                    ? SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.82,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => VideoCard(
                              video: videos[i],
                              onTap: () async {
                                await ref.read(globalPlayerControllerProvider.notifier)
                                    .playVideo(videos[i], queueVideos: videos, startIndex: i);
                                if (context.mounted) context.push(AppRoutes.videoPlayer);
                              },
                            ),
                            childCount: videos.length,
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        sliver: SliverList.builder(
                          itemCount: videos.length,
                          itemBuilder: (context, i) => VideoCard(
                            video: videos[i],
                            layout: MediaCardLayout.list,
                            onTap: () async {
                              await ref.read(globalPlayerControllerProvider.notifier)
                                  .playVideo(videos[i], queueVideos: videos, startIndex: i);
                              if (context.mounted) context.push(AppRoutes.videoPlayer);
                            },
                          ),
                        ),
                      ),
              if (audio.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  sliver: SliverList.builder(
                    itemCount: audio.length,
                    itemBuilder: (context, i) => AudioCard(
                      audio: audio[i],
                      onTap: () async {
                        await ref.read(globalPlayerControllerProvider.notifier)
                            .playAudio(audio[i], queueAudio: audio, startIndex: i);
                        if (context.mounted) context.push(AppRoutes.audioPlayer);
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

}
