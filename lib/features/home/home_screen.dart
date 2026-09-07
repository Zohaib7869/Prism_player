import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_boxes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/section_header.dart';
import '../../models/audio_model.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';
import 'widgets/continue_watching_card.dart';
import 'widgets/home_audio_tile.dart';
import 'widgets/quick_action_grid.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // The initial scan is now kicked off once by PermissionRequestGate in
  // main.dart, right after permissions are confirmed granted — not here.
  // This screen just watches the Hive boxes and rebuilds when rows land.
  // Pull-to-refresh below still triggers a manual full rescan on demand.
  bool _scanning = false;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final repo = ref.watch(mediaRepositoryProvider);

    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([
            Hive.box<VideoModel>(HiveBoxes.videos).listenable(),
            Hive.box<AudioModel>(HiveBoxes.audio).listenable(),
          ]),
          builder: (context, _) {
            final continueWatching = repo.continueWatching.take(10).toList();
            final recentAudio = repo.recentlyPlayedAudio.take(10).toList();
            final hasAnyMedia = repo.allVideos.isNotEmpty || repo.allAudio.isNotEmpty;

            return RefreshIndicator(
              onRefresh: () => ref.read(mediaRepositoryProvider).scan(fullRescan: true),
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _Header(scanning: _scanning)),
                  SliverToBoxAdapter(child: QuickActionGrid()),
                  if (!hasAnyMedia && !_scanning)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.video_library_outlined, size: 56, color: palette.textMuted),
                            const SizedBox(height: 12),
                            Text('No media found yet', style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text('Pull down to rescan your device for videos and music.',
                                style: TextStyle(color: palette.textMuted), textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  if (continueWatching.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: SectionHeader(title: 'Continue Watching', onSeeAll: () => context.push(AppRoutes.videos)),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 170,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: continueWatching.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => ContinueWatchingCard(video: continueWatching[i]),
                        ),
                      ),
                    ),
                  ],
                  if (recentAudio.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: SectionHeader(title: 'Recently Played', onSeeAll: () => context.push(AppRoutes.music)),
                    ),
                    SliverList.builder(
                      itemCount: recentAudio.length,
                      itemBuilder: (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: HomeAudioTile(audio: recentAudio[i]),
                      ),
                    ),
                  ],
                  SliverToBoxAdapter(child: _CategoryRow(
                    title: 'Videos',
                    chips: const ['All Videos', 'Recently Added', 'Large Videos', 'Folders'],
                    onTapChip: (_) => context.push(AppRoutes.videos),
                  )),
                  SliverToBoxAdapter(child: _CategoryRow(
                    title: 'Music',
                    chips: const ['Songs', 'Artists', 'Albums', 'Genres', 'Folders'],
                    onTapChip: (_) => context.push(AppRoutes.music),
                  )),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool scanning;
  const _Header({required this.scanning});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [palette.accent, palette.accentSecondary]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text('Prism Player', style: TextStyle(color: palette.textPrimary, fontSize: 20, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (scanning)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: palette.accent)),
            ),
          IconButton(icon: const Icon(Icons.search_rounded), onPressed: () => context.push(AppRoutes.search)),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => context.push(AppRoutes.settings)),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String title;
  final List<String> chips;
  final ValueChanged<String> onTapChip;
  const _CategoryRow({required this.title, required this.chips, required this.onTapChip});

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => ActionChip(
              label: Text(chips[i]),
              backgroundColor: palette.surface,
              labelStyle: TextStyle(color: palette.textPrimary),
              onPressed: () => onTapChip(chips[i]),
            ),
          ),
        ),
      ],
    );
  }
}
