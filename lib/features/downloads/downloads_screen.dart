import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/services/download_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../models/download_task.dart';
import '../../models/queue_item.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';

/// Everything the user has downloaded or is downloading, split the way they
/// think about it: what's in flight, saved videos, saved music.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final tasks = ref.watch(downloadManagerProvider);

    final active = tasks.where((t) => t.isPending).toList();
    final videos = tasks
        .where((t) => t.status == DownloadStatus.completed && !t.isAudioOnly)
        .toList();
    final audio = tasks
        .where((t) => t.status == DownloadStatus.completed && t.isAudioOnly)
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Downloads'),
          bottom: TabBar(
            labelColor: palette.accent,
            unselectedLabelColor: palette.textMuted,
            indicatorColor: palette.accent,
            tabs: [
              Tab(text: active.isEmpty ? 'Downloading' : 'Downloading (${active.length})'),
              const Tab(text: 'Video'),
              const Tab(text: 'Audio'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ActiveList(tasks: active),
            _CompletedList(tasks: videos, isAudio: false),
            _CompletedList(tasks: audio, isAudio: true),
          ],
        ),
      ),
    );
  }
}

class _ActiveList extends ConsumerWidget {
  final List<DownloadTask> tasks;
  const _ActiveList({required this.tasks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.isEmpty) {
      return const EmptyState(
        icon: Icons.download_done_rounded,
        title: 'Nothing downloading',
        message: 'Search YouTube in the Videos tab and tap the download icon on a result.',
      );
    }

    final palette = Theme.of(context).extension<PrismPalette>()!;
    final manager = ref.read(downloadManagerProvider.notifier);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        final task = tasks[i];
        final indeterminate = task.status == DownloadStatus.muxing ||
            (task.status == DownloadStatus.running && task.totalBytes == 0);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Thumb(task: task),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusLine(task),
                          style: TextStyle(
                            color: task.status == DownloadStatus.failed
                                ? palette.error
                                : palette.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _actionButton(context, palette, manager, task),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: indeterminate ? null : task.progress,
                  minHeight: 5,
                  backgroundColor: palette.divider,
                  valueColor: AlwaysStoppedAnimation(
                    task.status == DownloadStatus.failed ? palette.error : palette.accent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _statusLine(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.queued:
        return 'Waiting · ${task.qualityLabel}';
      case DownloadStatus.muxing:
        return 'Merging video and audio…';
      case DownloadStatus.paused:
        return 'Paused · ${Formatters.fileSize(task.receivedBytes)} of '
            '${Formatters.fileSize(task.totalBytes)}';
      case DownloadStatus.failed:
        return task.errorMessage ?? 'Download failed';
      case DownloadStatus.running:
        final percent = (task.progress * 100).toStringAsFixed(0);
        return '$percent% · ${Formatters.fileSize(task.receivedBytes)} of '
            '${Formatters.fileSize(task.totalBytes)} · ${task.qualityLabel}';
      case DownloadStatus.completed:
        return task.qualityLabel;
    }
  }

  Widget _actionButton(
    BuildContext context,
    PrismPalette palette,
    DownloadManager manager,
    DownloadTask task,
  ) {
    final canResume =
        task.status == DownloadStatus.paused || task.status == DownloadStatus.failed;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.status != DownloadStatus.muxing)
          IconButton(
            icon: Icon(
              canResume ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: palette.textSecondary,
            ),
            tooltip: canResume ? 'Resume' : 'Pause',
            onPressed: () => canResume ? manager.resumeTask(task.id) : manager.pause(task.id),
          ),
        IconButton(
          icon: Icon(Icons.close_rounded, color: palette.textMuted),
          tooltip: 'Cancel',
          onPressed: () => manager.remove(task.id),
        ),
      ],
    );
  }
}

class _CompletedList extends ConsumerWidget {
  final List<DownloadTask> tasks;
  final bool isAudio;
  const _CompletedList({required this.tasks, required this.isAudio});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tasks.isEmpty) {
      return EmptyState(
        icon: isAudio ? Icons.library_music_rounded : Icons.video_library_rounded,
        title: isAudio ? 'No downloaded music' : 'No downloaded videos',
        message: 'Finished downloads land here.',
      );
    }

    final palette = Theme.of(context).extension<PrismPalette>()!;

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final task = tasks[i];
        final exists = File(task.outputPath).existsSync();

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: _Thumb(task: task),
          title: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            exists
                ? '${task.qualityLabel} · ${Formatters.fileSize(task.totalBytes)} · '
                    '${Formatters.relativeDate(task.completedAtMs)}'
                : 'File missing — it may have been deleted',
            style: TextStyle(
              color: exists ? palette.textMuted : palette.warning,
              fontSize: 12,
            ),
          ),
          trailing: IconButton(
            icon: Icon(Icons.more_vert_rounded, color: palette.textMuted),
            onPressed: () => _showMenu(context, ref, task),
          ),
          onTap: exists ? () => _play(context, ref, task) : null,
        );
      },
    );
  }

  /// Plays a finished download through the app's own engine. These are ordinary
  /// local files by now, so they take the same path as anything scanned from
  /// storage — no streaming, no network.
  void _play(BuildContext context, WidgetRef ref, DownloadTask task) {
    final controller = ref.read(globalPlayerControllerProvider.notifier);
    final item = QueueItem(
      mediaRef: 'download:${task.id}',
      path: task.outputPath,
      title: task.title,
      artist: task.author,
      artUri: task.thumbnailUrl,
      durationMs: task.durationMs,
      isVideo: !task.isAudioOnly,
    );

    controller.playLocalFile(item);
    context.push(task.isAudioOnly ? AppRoutes.audioPlayer : AppRoutes.videoPlayer);
  }

  void _showMenu(BuildContext context, WidgetRef ref, DownloadTask task) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    showModalBottomSheet(
      context: context,
      backgroundColor: palette.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.info_outline_rounded, color: palette.textSecondary),
              title: Text('File location', style: TextStyle(color: palette.textPrimary)),
              subtitle: Text(
                task.outputPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.textMuted, fontSize: 11),
              ),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: palette.error),
              title: Text('Delete file', style: TextStyle(color: palette.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                ref.read(downloadManagerProvider.notifier).remove(task.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.playlist_remove_rounded, color: palette.textSecondary),
              title: Text('Remove from list only',
                  style: TextStyle(color: palette.textPrimary)),
              onTap: () {
                Navigator.pop(sheetContext);
                ref
                    .read(downloadManagerProvider.notifier)
                    .remove(task.id, deleteFile: false);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final DownloadTask task;
  const _Thumb({required this.task});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final placeholder = Container(
      width: 88,
      height: 52,
      color: palette.surfaceElevated,
      child: Icon(
        task.isAudioOnly ? Icons.music_note_rounded : Icons.movie_rounded,
        color: palette.textMuted,
        size: 20,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: task.thumbnailUrl == null
          ? placeholder
          : Image.network(
              task.thumbnailUrl!,
              width: 88,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}
