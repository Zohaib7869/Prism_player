import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_boxes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/media_bottom_sheet.dart';
import '../../core/widgets/playlist_picker_sheet.dart';
import '../../core/widgets/video_card.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';
import '../player/widgets/file_info_sheet.dart';
import 'widgets/youtube_results_list.dart';

enum VideoSort { name, date, size, duration }
enum VideoCategory { all, recentlyAdded, recentlyPlayed, large }

class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({super.key});

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  bool _grid = true;
  VideoSort _sort = VideoSort.date;
  VideoCategory _category = VideoCategory.all;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _ytQuery = '';
  bool _youtubeTab = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _ytQuery = value.trim());
    });
  }

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsRepositoryProvider);
    _grid = settings.gridViewDefault;
  }

  List<VideoModel> _apply(List<VideoModel> videos) {
    final q = _query.trim().toLowerCase();
    var list = q.isEmpty
        ? [...videos]
        : videos
            .where((v) =>
                v.title.toLowerCase().contains(q) || v.folderName.toLowerCase().contains(q))
            .toList();
    switch (_category) {
      case VideoCategory.all:
        break;
      case VideoCategory.recentlyAdded:
        list.sort((a, b) => b.dateModifiedMs.compareTo(a.dateModifiedMs));
        list = list.take(50).toList();
        break;
      case VideoCategory.recentlyPlayed:
        list = list.where((v) => v.lastPlayedAtMs > 0).toList()
          ..sort((a, b) => b.lastPlayedAtMs.compareTo(a.lastPlayedAtMs));
        break;
      case VideoCategory.large:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        list = list.take(50).toList();
        break;
    }
    switch (_sort) {
      case VideoSort.name:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case VideoSort.date:
        list.sort((a, b) => b.dateModifiedMs.compareTo(a.dateModifiedMs));
        break;
      case VideoSort.size:
        list.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case VideoSort.duration:
        list.sort((a, b) => b.durationMs.compareTo(a.durationMs));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final repo = ref.watch(mediaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Videos'),
        actions: [
          const _DownloadsButton(),
          IconButton(
            icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
            onPressed: () => setState(() => _grid = !_grid),
          ),
          PopupMenuButton<VideoSort>(
            icon: const Icon(Icons.sort_rounded),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (context) => const [
              PopupMenuItem(value: VideoSort.name, child: Text('Name')),
              PopupMenuItem(value: VideoSort.date, child: Text('Date')),
              PopupMenuItem(value: VideoSort.size, child: Text('Size')),
              PopupMenuItem(value: VideoSort.duration, child: Text('Duration')),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Hive.box<VideoModel>(HiveBoxes.videos).listenable(),
        builder: (context, _) {
          final videos = _apply(repo.allVideos);
          final searching = _query.trim().isNotEmpty;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(color: palette.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search device videos and YouTube',
                    hintStyle: TextStyle(color: palette.textMuted),
                    prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
                    suffixIcon: searching
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, color: palette.textMuted),
                            onPressed: () {
                              _searchController.clear();
                              _debounce?.cancel();
                              setState(() {
                                _query = '';
                                _ytQuery = '';
                                _youtubeTab = false;
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: palette.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (searching)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: Row(
                    children: [
                      _CategoryChip(
                        label: 'On device',
                        selected: !_youtubeTab,
                        onTap: () => setState(() => _youtubeTab = false),
                      ),
                      _CategoryChip(
                        label: 'YouTube',
                        selected: _youtubeTab,
                        onTap: () => setState(() => _youtubeTab = true),
                      ),
                    ],
                  ),
                ),
              if (searching && _youtubeTab)
                Expanded(child: YoutubeResultsList(query: _ytQuery.isEmpty ? _query.trim() : _ytQuery))
              else ...[
              if (!searching)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  children: [
                    _CategoryChip(label: 'All Videos', selected: _category == VideoCategory.all,
                        onTap: () => setState(() => _category = VideoCategory.all)),
                    _CategoryChip(label: 'Recently Added', selected: _category == VideoCategory.recentlyAdded,
                        onTap: () => setState(() => _category = VideoCategory.recentlyAdded)),
                    _CategoryChip(label: 'Recently Played', selected: _category == VideoCategory.recentlyPlayed,
                        onTap: () => setState(() => _category = VideoCategory.recentlyPlayed)),
                    _CategoryChip(label: 'Large Videos', selected: _category == VideoCategory.large,
                        onTap: () => setState(() => _category = VideoCategory.large)),
                    _CategoryChip(label: 'Folders', selected: false, onTap: () => context.push(AppRoutes.folders)),
                  ],
                ),
              ),
              Expanded(
                child: videos.isEmpty
                    ? EmptyState(
                        icon: Icons.movie_outlined,
                        title: searching ? 'No matching videos' : 'No videos found',
                        message: searching
                            ? 'Nothing on this device matches "${_query.trim()}". Try the YouTube tab.'
                            : 'Videos on your device will show up here.')
                    : _grid
                        ? GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.82,
                            ),
                            itemCount: videos.length,
                            itemBuilder: (context, i) => _buildCard(context, videos, i, MediaCardLayout.grid),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: videos.length,
                            itemBuilder: (context, i) => _buildCard(context, videos, i, MediaCardLayout.list),
                          ),
              ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildCard(BuildContext context, List<VideoModel> videos, int i, MediaCardLayout layout) {
    final video = videos[i];
    return VideoCard(
      video: video,
      layout: layout,
      onTap: () async {
        await ref.read(globalPlayerControllerProvider.notifier).playVideo(video, queueVideos: videos, startIndex: i);
        if (context.mounted) context.push(AppRoutes.videoPlayer);
      },
      onMore: () => _showActions(context, video),
    );
  }

  void _showActions(BuildContext context, VideoModel video) {
    final repo = ref.read(mediaRepositoryProvider);
    showMediaBottomSheet(
      context: context,
      title: video.title,
      subtitle: video.folderName,
      actions: [
        SheetAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          onTap: () async {
            await ref.read(globalPlayerControllerProvider.notifier).playVideo(video);
            if (context.mounted) context.push(AppRoutes.videoPlayer);
          },
        ),
        SheetAction(
          icon: video.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          label: video.isFavorite ? 'Remove from favorites' : 'Add to favorites',
          onTap: () => repo.toggleVideoFavorite(video.id),
        ),
        SheetAction(
          icon: Icons.playlist_add_rounded,
          label: 'Add to playlist',
          onTap: () => showPlaylistPickerSheet(context: context, ref: ref, mediaRef: video.mediaRef),
        ),
        SheetAction(
          icon: Icons.drive_file_rename_outline_rounded,
          label: 'Rename',
          onTap: () async {
            final newName = await showTextInputDialog(context: context, title: 'Rename video', initialValue: video.title);
            if (newName != null && newName.isNotEmpty) await repo.renameVideo(video.id, newName);
          },
        ),
        SheetAction(
          icon: Icons.info_outline_rounded,
          label: 'File information',
          onTap: () => showFileInfoSheet(context: context, video: video),
        ),
        SheetAction(
          icon: Icons.share_rounded,
          label: 'Share',
          onTap: () {}, // wired via share_plus in the video player screen's share button
        ),
        SheetAction(
          icon: Icons.visibility_off_rounded,
          label: 'Hide (move to Safe)',
          onTap: () => repo.setVideoHidden(video.id, true),
        ),
        SheetAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          destructive: true,
          onTap: () async {
            final confirmed = await showConfirmDialog(
              context: context, title: 'Delete video', message: 'This permanently deletes "${video.title}" from your device.');
            if (confirmed == true) await repo.deleteVideo(video.id);
          },
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: palette.accent.withOpacity(0.25),
        backgroundColor: palette.surface,
        labelStyle: TextStyle(color: selected ? palette.accent : palette.textPrimary),
      ),
    );
  }
}

/// App-bar entry point to the Downloads screen, with a badge showing how many
/// transfers are still in flight so the user can walk away from a download and
/// still know it's running.
class _DownloadsButton extends ConsumerWidget {
  const _DownloadsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final activeCount = ref.watch(activeDownloadCountProvider);

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.download_rounded),
          tooltip: 'Downloads',
          onPressed: () => context.push(AppRoutes.downloads),
        ),
        if (activeCount > 0)
          Positioned(
            top: 8,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$activeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
