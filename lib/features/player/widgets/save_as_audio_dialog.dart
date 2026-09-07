import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/audio_extraction_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/audio_model.dart';
import '../../../models/video_model.dart';
import '../../../providers/app_providers.dart';

/// Drives "Save as Audio": extracts the audio track from [video] into a
/// standalone .m4a file via the native MediaExtractor/MediaMuxer pipeline,
/// shows live progress, and — on success — registers the result as a real
/// AudioModel so it appears in the Music tab immediately.
Future<void> showSaveAsAudioDialog(BuildContext context, WidgetRef ref, VideoModel video) async {
  final extractionService = ref.read(audioExtractionServiceProvider);
  final musicDir = Directory('${(await getExternalStorageDirectory())!.path}/Music');
  if (!await musicDir.exists()) await musicDir.create(recursive: true);
  final safeName = video.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
  final outputPath = '${musicDir.path}/$safeName.m4a';

  if (!context.mounted) return;
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _ExtractionDialog(
      video: video,
      outputPath: outputPath,
      stream: extractionService.extractAudio(sourcePath: video.path, outputPath: outputPath),
      onCancel: () => extractionService.cancel(),
    ),
  );
}

class _ExtractionDialog extends ConsumerStatefulWidget {
  final VideoModel video;
  final String outputPath;
  final Stream<ExtractionEvent> stream;
  final VoidCallback onCancel;

  const _ExtractionDialog({
    required this.video,
    required this.outputPath,
    required this.stream,
    required this.onCancel,
  });

  @override
  ConsumerState<_ExtractionDialog> createState() => _ExtractionDialogState();
}

class _ExtractionDialogState extends ConsumerState<_ExtractionDialog> {
  int _progress = 0;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    widget.stream.listen((event) async {
      if (!mounted) return;
      switch (event) {
        case ExtractionProgress(:final percent):
          setState(() => _progress = percent);
        case ExtractionDone(:final outputPath):
          await _onSuccess(outputPath);
        case ExtractionError(:final message):
          setState(() => _error = message);
        case ExtractionCancelled():
          if (mounted) Navigator.of(context).pop();
      }
    });
  }

  Future<void> _onSuccess(String outputPath) async {
    final file = File(outputPath);
    final size = await file.exists() ? await file.length() : 0;
    final audioModel = AudioModel(
      id: 'extracted_${const Uuid().v4()}',
      path: outputPath,
      title: widget.video.title,
      artist: 'Extracted Audio',
      album: 'Saved from Video',
      durationMs: widget.video.durationMs,
      sizeBytes: size,
      dateModifiedMs: DateTime.now().millisecondsSinceEpoch,
      folderName: 'Music',
      folderPath: file.parent.path,
      mimeType: 'audio/mp4',
    );
    await ref.read(mediaRepositoryProvider).registerExtractedAudio(audioModel);
    await ref.read(mediaScannerServiceProvider).rescan(outputPath);
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return AlertDialog(
      title: const Text('Save as Audio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            Icon(Icons.error_outline_rounded, color: palette.error, size: 32),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: palette.error)),
          ] else if (_done) ...[
            Icon(Icons.check_circle_rounded, color: palette.success, size: 32),
            const SizedBox(height: 8),
            const Text('Audio saved and added to your Music library.'),
          ] else ...[
            Text('Extracting audio from "${widget.video.title}"…'),
            const SizedBox(height: 16),
            // backgroundColor (the unfilled "track") wasn't set here before,
            // so it fell back to the theme's implicit default — which in
            // this app's dark palettes renders close enough to `accent`
            // that the bar looked fully filled from 0% onward even though
            // the percent text underneath was updating correctly. Match the
            // rest of the app's own convention (see sliderTheme's
            // inactiveTrackColor) so the empty portion is clearly distinct.
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress / 100,
                minHeight: 6,
                color: palette.accent,
                backgroundColor: palette.divider,
              ),
            ),
            const SizedBox(height: 8),
            Text('$_progress%', style: TextStyle(color: palette.textMuted)),
          ],
        ],
      ),
      actions: [
        if (!_done && _error == null)
          TextButton(
            onPressed: () {
              widget.onCancel();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
        if (_done || _error != null)
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
