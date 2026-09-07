import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/youtube_native_download_resolver.dart';
import '../../../core/services/youtube_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/app_providers.dart';
import '../../../repositories/download_repository.dart';

/// Quality picker for a YouTube download: every mp4 resolution first, then the
/// audio-only entries under a "Music" heading.
///
/// Prefers the native yt-dlp path when available (YoutubeNativeService) —
/// its extract_info chain gets past YouTube's bot-check where the legacy
/// youtube_explode_dart manifest keeps getting 403'd, so downloads through
/// here actually land at the quality picked instead of silently collapsing
/// to 360p. Only the format *catalog* is fetched to build this list; the
/// real signed URL for whichever quality gets tapped is resolved once, in
/// [_start] — not for every row up front. Falls back to the legacy
/// youtube_explode_dart listing if native is unavailable or fails.
class DownloadOptionsSheet extends ConsumerStatefulWidget {
  final String videoId;
  final String title;
  final String? author;
  final String? thumbnailUrl;
  final int durationMs;

  const DownloadOptionsSheet({
    super.key,
    required this.videoId,
    required this.title,
    this.author,
    this.thumbnailUrl,
    this.durationMs = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required String videoId,
    required String title,
    String? author,
    String? thumbnailUrl,
    int durationMs = 0,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DownloadOptionsSheet(
        videoId: videoId,
        title: title,
        author: author,
        thumbnailUrl: thumbnailUrl,
        durationMs: durationMs,
      ),
    );
  }

  @override
  ConsumerState<DownloadOptionsSheet> createState() => _DownloadOptionsSheetState();
}

class _DownloadOptionsSheetState extends ConsumerState<DownloadOptionsSheet> {
  late Future<List<YoutubeDownloadOption>> _future;

  /// True once we know this session's list came from the native yt-dlp path
  /// (real qualities, URLs resolved lazily per-tap in [_start]) rather than
  /// the legacy youtube_explode_dart manifest — used only to route [_start].
  bool _usingNative = false;

  @override
  void initState() {
    super.initState();
    _future = _loadOptions();
  }

  Future<List<YoutubeDownloadOption>> _loadOptions() async {
    final native = ref.read(youtubeNativeServiceProvider);
    try {
      if (await native.isAvailable()) {
        final resolver = YoutubeNativeDownloadResolver(native);
        final formats = await resolver.listFormats(widget.videoId);
        final options = resolver.buildPlaceholderOptions(formats);
        if (options.isNotEmpty) {
          _usingNative = true;
          return options;
        }
      }
    } catch (_) {
      // Native path unavailable/failed for this video — fall through to the
      // legacy youtube_explode_dart listing below rather than showing an
      // empty sheet.
    }
    _usingNative = false;
    return ref.read(youtubeServiceProvider).getDownloadOptions(widget.videoId);
  }

  Future<void> _start(YoutubeDownloadOption option) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Read every provider up front. Resolving a quality is a network round
    // trip, and if the sheet is dismissed while it is in flight this State is
    // disposed — a `ref.read` afterwards throws
    // "Cannot use ref after the widget was disposed" and the download is
    // silently never queued.
    final nativeService = ref.read(youtubeNativeServiceProvider);
    final downloads = ref.read(downloadManagerProvider.notifier);

    var resolved = option;
    if (_usingNative && option.nativeFormatSelector != null) {
      try {
        resolved = await YoutubeNativeDownloadResolver(nativeService)
            .resolve(widget.videoId, option);
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Could not fetch that quality: $e')),
          );
        }
        return;
      }
    }

    await downloads.enqueue(
          videoId: widget.videoId,
          title: widget.title,
          option: resolved,
          author: widget.author,
          thumbnailUrl: widget.thumbnailUrl,
          durationMs: widget.durationMs,
        );
    if (navigator.mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Downloading ${widget.title} · ${resolved.label}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final repository = ref.watch(downloadRepositoryProvider);
    // Watched so the "Downloaded" markers update if something finishes while
    // this sheet is open.
    ref.watch(downloadManagerProvider);

    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: palette.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(Icons.download_rounded, color: palette.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: palette.divider, height: 1),
          Flexible(
            child: FutureBuilder<List<YoutubeDownloadOption>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError || (snapshot.data?.isEmpty ?? true)) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No downloadable formats available for this video.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: palette.textMuted),
                    ),
                  );
                }

                final options = snapshot.data!;
                final video = options.where((o) => !o.audioOnly).toList();
                final audio = options.where((o) => o.audioOnly).toList();

                return ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: 8),
                  children: [
                    if (video.isNotEmpty) _header(palette, 'Video'),
                    ...video.map((o) => _row(palette, repository, o)),
                    if (audio.isNotEmpty) _header(palette, 'Music'),
                    ...audio.map((o) => _row(palette, repository, o)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(PrismPalette palette, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _row(PrismPalette palette, DownloadRepository repository, YoutubeDownloadOption option) {
    final done = repository.alreadyHas(
      widget.videoId,
      option.label,
      audioOnly: option.audioOnly,
    );

    return ListTile(
      leading: Icon(
        option.audioOnly ? Icons.music_note_rounded : Icons.movie_rounded,
        color: done ? palette.success : palette.accent,
      ),
      title: Text(
        option.label,
        style: TextStyle(color: palette.textPrimary, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          option.extension.toUpperCase(),
          if (option.totalBytes > 0) Formatters.fileSize(option.totalBytes),
        ].join(' · '),
        style: TextStyle(color: palette.textMuted, fontSize: 12),
      ),
      trailing: done
          ? Icon(Icons.check_circle_rounded, color: palette.success)
          : Icon(Icons.download_rounded, color: palette.textMuted),
      onTap: done ? null : () => _start(option),
    );
  }
}
