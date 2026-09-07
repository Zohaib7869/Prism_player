import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/database/hive_boxes.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/audio_card.dart';
import '../../core/widgets/folder_card.dart';
import '../../core/widgets/video_card.dart';
import '../../models/audio_model.dart';
import '../../models/video_model.dart';
import '../../providers/app_providers.dart';
import '../../routes/app_router.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final repo = ref.watch(mediaRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search videos, music, folders…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(icon: const Icon(Icons.close_rounded), onPressed: () {
              _controller.clear();
              setState(() => _query = '');
            }),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          Hive.box<VideoModel>(HiveBoxes.videos).listenable(),
          Hive.box<AudioModel>(HiveBoxes.audio).listenable(),
        ]),
        builder: (context, _) {
          final results = repo.search(_query);
          return _query.isEmpty
              ? Center(child: Text('Search your library', style: TextStyle(color: palette.textMuted)))
              : results.isEmpty
                  ? Center(child: Text('No results for "$_query"', style: TextStyle(color: palette.textMuted)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                      children: [
                        if (results.videos.isNotEmpty) ...[
                          _CategoryLabel('Videos (${results.videos.length})', palette),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.82,
                            ),
                            itemCount: results.videos.length,
                            itemBuilder: (context, i) => VideoCard(
                              video: results.videos[i],
                              onTap: () async {
                                await ref.read(globalPlayerControllerProvider.notifier).playVideo(results.videos[i]);
                                if (context.mounted) context.push(AppRoutes.videoPlayer);
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (results.songs.isNotEmpty) ...[
                          _CategoryLabel('Music (${results.songs.length})', palette),
                          for (final s in results.songs)
                            AudioCard(
                              audio: s,
                              onTap: () async {
                                await ref.read(globalPlayerControllerProvider.notifier).playAudio(s);
                                if (context.mounted) context.push(AppRoutes.audioPlayer);
                              },
                            ),
                          const SizedBox(height: 16),
                        ],
                        if (results.folders.isNotEmpty) ...[
                          _CategoryLabel('Folders (${results.folders.length})', palette),
                          for (final f in results.folders)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FolderCard(folder: f, onTap: () => context.push('/folders/detail', extra: f.path)),
                            ),
                        ],
                        if (results.artists.isNotEmpty) ...[
                          _CategoryLabel('Artists (${results.artists.length})', palette),
                          for (final a in results.artists)
                            ListTile(
                              leading: Icon(Icons.person_rounded, color: palette.accent),
                              title: Text(a),
                              onTap: () => context.push(AppRoutes.music),
                            ),
                        ],
                        if (results.albums.isNotEmpty) ...[
                          _CategoryLabel('Albums (${results.albums.length})', palette),
                          for (final a in results.albums)
                            ListTile(
                              leading: Icon(Icons.album_rounded, color: palette.accent),
                              title: Text(a),
                              onTap: () => context.push(AppRoutes.music),
                            ),
                        ],
                      ],
                    );
        },
      ),
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  final String text;
  final PrismPalette palette;
  const _CategoryLabel(this.text, this.palette);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: TextStyle(color: palette.textMuted, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
