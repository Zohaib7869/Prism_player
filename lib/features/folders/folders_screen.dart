import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_boxes.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/folder_card.dart';
import '../../core/widgets/media_bottom_sheet.dart';
import '../../models/audio_model.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';

enum FolderFilter { all, videos, audio }

class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  FolderFilter _filter = FolderFilter.all;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(mediaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Folders'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: SegmentedButton<FolderFilter>(
              segments: const [
                ButtonSegment(value: FolderFilter.all, label: Text('All')),
                ButtonSegment(value: FolderFilter.videos, label: Text('Videos')),
                ButtonSegment(value: FolderFilter.audio, label: Text('Audio')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
        ),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          Hive.box<VideoModel>(HiveBoxes.videos).listenable(),
          Hive.box<AudioModel>(HiveBoxes.audio).listenable(),
          Hive.box(HiveBoxes.hiddenFolders).listenable(),
        ]),
        builder: (context, _) {
          final folders = switch (_filter) {
            FolderFilter.all => repo.allFolders,
            FolderFilter.videos => repo.videoFolders,
            FolderFilter.audio => repo.audioFolders,
          };
          if (folders.isEmpty) {
            return const EmptyState(icon: Icons.folder_outlined, title: 'No folders found');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            itemCount: folders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final folder = folders[i];
              return FolderCard(
                folder: folder,
                onTap: () => context.push('/folders/detail', extra: folder.path),
                onMore: () => showMediaBottomSheet(
                  context: context,
                  title: folder.name,
                  subtitle: '${folder.totalCount} items',
                  actions: [
                    SheetAction(
                      icon: Icons.visibility_off_rounded,
                      label: 'Hide folder (move to Safe)',
                      onTap: () => repo.setFolderHidden(folder.path, true),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
