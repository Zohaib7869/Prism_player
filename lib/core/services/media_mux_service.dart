import 'dart:async';

import 'package:flutter/services.dart';

/// Dart side of [MediaMuxPlugin]. Merges a downloaded video-only file with its
/// audio-only counterpart into one playable MP4, by stream copy — see the
/// Kotlin doc comment for why this is seconds rather than minutes.
class MediaMuxService {
  static const _methodChannel = MethodChannel('com.prismplayer.app/media_mux');
  static const _eventChannel = EventChannel('com.prismplayer.app/media_mux_progress');

  /// Completes with the output path, or throws with the native error message.
  ///
  /// The subscription is opened *before* the mux is kicked off, because the
  /// native side starts emitting as soon as it is told to run and a short file
  /// can finish before a listener attached afterwards would ever see it.
  /// Copies the audio track out of [sourcePath] into a standalone .m4a at
  /// [outputPath], by stream copy. Used when an audio download has to fall
  /// back to YouTube's progressive (video+audio) file because the adaptive
  /// audio URL is refused.
  Future<String> extractAudio({
    required String sourcePath,
    required String outputPath,
    void Function(int percent)? onProgress,
  }) async {
    final completer = Completer<String>();
    late final StreamSubscription subscription;

    subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        final map = Map<String, dynamic>.from(event as Map);
        switch (map['status']) {
          case 'progress':
            onProgress?.call(map['progress'] as int? ?? 0);
            break;
          case 'done':
            if (!completer.isCompleted) {
              completer.complete(map['outputPath'] as String? ?? outputPath);
            }
            break;
          case 'cancelled':
            if (!completer.isCompleted) {
              completer.completeError(StateError('Extraction cancelled'));
            }
            break;
          case 'error':
          default:
            if (!completer.isCompleted) {
              completer.completeError(
                StateError(map['message'] as String? ?? 'Unknown extraction error'),
              );
            }
            break;
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    try {
      await _methodChannel.invokeMethod('extractAudio', {
        'sourcePath': sourcePath,
        'outputPath': outputPath,
      });
      return await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  Future<String> mux({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    void Function(int percent)? onProgress,
  }) async {
    final completer = Completer<String>();
    late final StreamSubscription subscription;

    subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        final map = Map<String, dynamic>.from(event as Map);
        switch (map['status']) {
          case 'progress':
            onProgress?.call(map['progress'] as int? ?? 0);
            break;
          case 'done':
            if (!completer.isCompleted) {
              completer.complete(map['outputPath'] as String? ?? outputPath);
            }
            break;
          case 'cancelled':
            if (!completer.isCompleted) {
              completer.completeError(StateError('Merge cancelled'));
            }
            break;
          case 'error':
          default:
            if (!completer.isCompleted) {
              completer.completeError(
                StateError(map['message'] as String? ?? 'Unknown merge error'),
              );
            }
            break;
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    try {
      await _methodChannel.invokeMethod('mux', {
        'videoPath': videoPath,
        'audioPath': audioPath,
        'outputPath': outputPath,
      });
      return await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> cancel() => _methodChannel.invokeMethod('cancelMux');
}
