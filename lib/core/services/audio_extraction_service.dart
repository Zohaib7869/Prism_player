import 'package:flutter/services.dart';

sealed class ExtractionEvent {
  const ExtractionEvent();
}

class ExtractionProgress extends ExtractionEvent {
  final int percent;
  const ExtractionProgress(this.percent);
}

class ExtractionDone extends ExtractionEvent {
  final String outputPath;
  const ExtractionDone(this.outputPath);
}

class ExtractionError extends ExtractionEvent {
  final String message;
  const ExtractionError(this.message);
}

class ExtractionCancelled extends ExtractionEvent {
  const ExtractionCancelled();
}

/// Drives the native "Save as Audio" pipeline: extracts the compressed audio
/// track out of a video file into a standalone .m4a using MediaExtractor /
/// MediaMuxer (real stream copy, not a fake/simulated conversion — see the
/// Kotlin implementation for the exact codec constraints).
class AudioExtractionService {
  static const _methodChannel = MethodChannel('com.prismplayer.app/audio_extraction');
  static const _eventChannel = EventChannel('com.prismplayer.app/audio_extraction_progress');

  Stream<ExtractionEvent> extractAudio({
    required String sourcePath,
    required String outputPath,
  }) {
    final controller = _eventChannel.receiveBroadcastStream().map<ExtractionEvent>((event) {
      final map = Map<String, dynamic>.from(event as Map);
      switch (map['status']) {
        case 'progress':
          return ExtractionProgress(map['progress'] as int);
        case 'done':
          return ExtractionDone(map['outputPath'] as String);
        case 'cancelled':
          return const ExtractionCancelled();
        case 'error':
        default:
          return ExtractionError(map['message'] as String? ?? 'Unknown error');
      }
    });

    // Kick the native extraction off; the caller should subscribe to the
    // returned stream before (or immediately after) this resolves.
    _methodChannel.invokeMethod('extractAudio', {
      'sourcePath': sourcePath,
      'outputPath': outputPath,
    });

    return controller;
  }

  Future<void> cancel() => _methodChannel.invokeMethod('cancelExtraction');
}
