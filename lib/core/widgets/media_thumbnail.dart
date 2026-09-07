import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// Displays a video thumbnail file, audio album-art content URI, or a
/// themed fallback icon — used by every media card in the app so thumbnail
/// rendering logic lives in exactly one place.
class MediaThumbnail extends ConsumerStatefulWidget {
  final String? path; // local file path (video thumbnail cache) or content:// uri
  final bool isVideo;
  final double borderRadius;
  final BoxFit fit;

  const MediaThumbnail({
    super.key,
    required this.path,
    required this.isVideo,
    this.borderRadius = 12,
    this.fit = BoxFit.cover,
  });

  @override
  ConsumerState<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends ConsumerState<MediaThumbnail> {
  Future<Uint8List?>? _artFuture;
  String? _artFuturePath;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final path = widget.path;

    Widget fallback() => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [palette.surfaceElevated, palette.surface],
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.isVideo ? Icons.movie_rounded : Icons.music_note_rounded,
            color: palette.textMuted,
            size: 28,
          ),
        );

    Widget content;
    if (path == null || path.isEmpty) {
      content = fallback();
    } else if (path.startsWith('content://')) {
      final artService = ref.read(albumArtServiceProvider);
      if (artService.has(path)) {
        // Already resolved (e.g. prefetched by GlobalPlayerController before
        // navigating here, or loaded by an earlier card for the same art) —
        // render it synchronously in this same build. Going through
        // FutureBuilder here would still show one blank/loading frame even
        // though the data is already sitting in memory, since a Future only
        // ever reports "done" on a later microtask — that one frame is what
        // showed up as a brief flicker whenever a fresh widget instance
        // (a new list row, a Hero destination, a re-pushed screen) first
        // built for art that had, in fact, already loaded.
        final cached = artService.peek(path);
        content = cached == null
            ? fallback()
            : Image.memory(cached, fit: widget.fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => fallback());
      } else {
        // The parent (e.g. the Now Playing screen) can rebuild many times a
        // second while a track is playing (position ticks, etc). Re-reading
        // widget.path directly in `future:` on every build would kick the
        // FutureBuilder back to "waiting" each time and flash the art out —
        // that was the cause of the Now Playing screen "blinking" and the
        // Hero transition getting visually stuck mid-slide. Only kick off a
        // new load when the path itself actually changes.
        if (_artFuturePath != path) {
          _artFuturePath = path;
          _artFuture = artService.load(path);
        }
        content = FutureBuilder<Uint8List?>(
          future: _artFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Container(color: palette.surface);
            }
            if (snapshot.data == null) return fallback();
            return Image.memory(snapshot.data!, fit: widget.fit, gaplessPlayback: true, errorBuilder: (_, __, ___) => fallback());
          },
        );
      }
    } else {
      content = Image.file(
        File(path),
        fit: widget.fit,
        // Keeps showing the previous frame instead of flashing blank when
        // this widget rebuilds with a path that hasn't changed but is a new
        // widget instance (e.g. list rebuilds triggered by an unrelated Hive
        // field change elsewhere in the box) — see video_card.dart's note on
        // why those rebuilds happen.
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: content,
    );
  }
}
