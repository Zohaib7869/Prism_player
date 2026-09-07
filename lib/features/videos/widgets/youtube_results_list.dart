import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/youtube_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../providers/app_providers.dart';
import '../../../routes/app_router.dart';
import '../../downloads/widgets/download_options_sheet.dart';

/// Debounced YouTube search results for the Videos screen. Tapping a result
/// resolves a direct stream URL and hands it to the app's own player, so
/// playback happens inside Prism with all the usual gestures and controls.
class YoutubeResultsList extends ConsumerStatefulWidget {
  final String query;
  const YoutubeResultsList({super.key, required this.query});

  @override
  ConsumerState<YoutubeResultsList> createState() => _YoutubeResultsListState();
}

class _YoutubeResultsListState extends ConsumerState<YoutubeResultsList> {
  Future<List<YoutubeSearchResult>>? _future;
  String _loadedQuery = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(covariant YoutubeResultsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _run();
  }

  void _run() {
    final q = widget.query.trim();
    if (q.isEmpty || q == _loadedQuery) return;
    _loadedQuery = q;
    setState(() {
      _future = ref.read(youtubeServiceProvider).search(q).then((results) {
        // Warm up the stream URL for the first couple of results while the
        // user is still looking at the list — these are the ones most
        // likely to get tapped, so by the time they do, resolveStreamUrl
        // just returns the cached value instead of making them wait.
        final service = ref.read(youtubeServiceProvider);
        for (final r in results.take(4)) {
          service.prefetchStream(r.videoId);
        }
        return results;
      });
    });
  }

  /// Opens the player screen *immediately* and lets the stream resolve in the
  /// background.
  ///
  /// This used to `await resolveStreamUrl` behind a full-screen blocking
  /// spinner before navigating — and that resolve walks several YouTube
  /// client profiles, each costing a manifest fetch plus playability probes,
  /// so on a mobile connection the user sat on the results list for many
  /// seconds with nothing happening. The player screen renders its own
  /// loading state (and its own error state) while no controller is attached,
  /// so there is nothing to wait for here.
  void _play(YoutubeSearchResult result) {
    unawaited(ref.read(globalPlayerControllerProvider.notifier).openYoutube(
          videoId: result.videoId,
          title: result.title,
          author: result.author,
          thumbnailUrl: result.thumbnailUrl,
          durationMs: result.durationMs,
        ));
    context.push(AppRoutes.videoPlayer);
  }

  String _duration(int ms) {
    if (ms <= 0) return '';
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;

    return Stack(
      children: [
        FutureBuilder<List<YoutubeSearchResult>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Search failed',
                message: 'Check your internet connection and try again.',
              );
            }
            final results = snapshot.data ?? const <YoutubeSearchResult>[];
            if (results.isEmpty) {
              return const EmptyState(
                icon: Icons.play_circle_outline_rounded,
                title: 'No YouTube results',
                message: 'Try a different search term.',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              itemCount: results.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final r = results[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _play(r),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          children: [
                            Image.network(
                              r.thumbnailUrl,
                              width: 132,
                              height: 76,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 132,
                                height: 76,
                                color: palette.surface,
                                child: Icon(Icons.movie_rounded, color: palette.textMuted),
                              ),
                            ),
                            if (_duration(r.durationMs).isNotEmpty)
                              Positioned(
                                right: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _duration(r.durationMs),
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              r.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: palette.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.download_rounded, color: palette.textSecondary),
                        tooltip: 'Download',
                        onPressed: () => DownloadOptionsSheet.show(
                          context,
                          videoId: r.videoId,
                          title: r.title,
                          author: r.author,
                          thumbnailUrl: r.thumbnailUrl,
                          durationMs: r.durationMs,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}
