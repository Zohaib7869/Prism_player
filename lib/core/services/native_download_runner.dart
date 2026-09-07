import 'dart:async';

import '../../models/youtube_native_download_event.dart';
import 'download_service.dart' show DownloadCancelled, DownloadHandle;
import 'youtube_native_service.dart';
import 'yt_log.dart';

/// Runs a transfer inside yt-dlp instead of over Dart's HttpClient.
///
/// WHY
/// ---
/// SegmentedDownloader fetches a URL that yt-dlp resolved in a *different*
/// HTTP session. For adaptive googlevideo URLs that fails with 403 no matter
/// which headers are replayed, because the URL is bound to the session that
/// minted it. This class keeps resolution and transfer in the same place,
/// which is how yt-dlp is meant to be driven.
///
/// DROP-IN
/// -------
/// [download] deliberately mirrors `SegmentedDownloader.download`'s signature
/// (url/savePath/handle/knownSize/onProgress) so DownloadManager can switch
/// between the two without restructuring `_downloadStreams`. The one
/// difference: this takes a [formatSelector] and a [videoUrl] (the watch page
/// URL, not a stream URL), because yt-dlp re-resolves internally.
///
/// SINGLE FORMAT ONLY
/// ------------------
/// The selector must not contain '+'. A merging selector makes yt-dlp shell
/// out to ffmpeg, which this build does not ship. Callers download video and
/// audio as two jobs and join them with MediaMuxService, which already works.
class NativeDownloadRunner {
  final YoutubeNativeService native;

  NativeDownloadRunner(this.native);

  /// Broadcast subscription shared by all in-flight jobs — the EventChannel
  /// carries every job's events and each caller filters by downloadId.
  Stream<YoutubeNativeDownloadEvent>? _events;

  Stream<YoutubeNativeDownloadEvent> get _stream =>
      _events ??= native.downloadEvents.asBroadcastStream();

  /// Transfers one format to [savePath].
  ///
  /// Completes when the native side reports `completed`. Throws
  /// [DownloadCancelled] on cancel, or [NativeDownloadFailure] with a
  /// classified code on failure.
  Future<String> download({
    required String watchUrl,
    required String formatSelector,
    required String savePath,
    required String downloadId,
    required DownloadHandle handle,
    int? knownSize,
    void Function(int received, int total)? onProgress,
  }) async {
    assert(
      !formatSelector.contains('+'),
      'NativeDownloadRunner needs a single-format selector; "$formatSelector" '
      'would require an ffmpeg merge that this build cannot perform.',
    );

    YtLog.download('request started id=$downloadId selector=$formatSelector');
    YtLog.file('target path=$savePath');

    final completer = Completer<String>();
    late final StreamSubscription<YoutubeNativeDownloadEvent> sub;

    // Subscribe before starting, so a very short transfer cannot finish before
    // a listener attached afterwards would see it — the same ordering rule
    // MediaMuxService already follows.
    sub = _stream.where((e) => e.downloadId == downloadId).listen(
      (event) {
        switch (event.type) {
          case YoutubeNativeDownloadEventType.started:
            YtLog.download('native job accepted id=$downloadId');
            break;

          case YoutubeNativeDownloadEventType.progress:
            final received = _bytesFrom(event, knownSize);
            if (received != null) {
              final total = (event.totalBytes ?? 0) > 0
                  ? event.totalBytes!
                  : (knownSize ?? 0);
              // Throttled so a fast transfer cannot spam the log; the native
              // poller already fires at 500ms, this keeps logs to ~1/sec.
              final now = DateTime.now();
              if (_lastLog == null ||
                  now.difference(_lastLog!) >= const Duration(seconds: 1)) {
                _lastLog = now;
                YtLog.download(
                  'progress id=$downloadId ${received ~/ 1024}KiB'
                  '${total > 0 ? " / ${total ~/ 1024}KiB" : ""}',
                );
              }
              onProgress?.call(received, total);
            }
            break;

          case YoutubeNativeDownloadEventType.completed:
            YtLog.download('completed id=$downloadId');
            YtLog.file('final path=${event.outputPath ?? savePath}');
            if (!completer.isCompleted) {
              completer.complete(event.outputPath ?? savePath);
            }
            break;

          case YoutubeNativeDownloadEventType.cancelled:
            YtLog.download('cancelled id=$downloadId');
            if (!completer.isCompleted) {
              completer.completeError(const DownloadCancelled());
            }
            break;

          case YoutubeNativeDownloadEventType.failed:
            final code = event.errorCode ?? 'DOWNLOAD_FAILED';
            YtLog.download('failed id=$downloadId code=$code');
            if (!completer.isCompleted) {
              completer.completeError(
                NativeDownloadFailure(code, event.errorMessage ?? 'Download failed'),
              );
            }
            break;
        }
      },
      onError: (Object e, StackTrace s) {
        YtLog.error('DOWNLOAD', e, s);
        if (!completer.isCompleted) completer.completeError(e);
      },
    );

    // Cancellation is cooperative: the handle is polled while the native job
    // runs, and a cancel is forwarded so yt-dlp's own loop stops.
    Timer? cancelWatch;
    cancelWatch = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (handle.isCancelled) {
        cancelWatch?.cancel();
        YtLog.download('forwarding cancel to native id=$downloadId');
        unawaited(native.cancelDownload(downloadId).catchError((Object e) {
          YtLog.error('DOWNLOAD', e);
        }));
      }
    });

    try {
      await native.download(
        url: watchUrl,
        formatSelector: formatSelector,
        outputTemplate: savePath,
        downloadId: downloadId,
      );
      return await completer.future;
    } finally {
      cancelWatch.cancel();
      await sub.cancel();
    }
  }

  DateTime? _lastLog;

  /// ROOT CAUSE of "downloads complete but show no progress": this used to read
  /// only [YoutubeNativeDownloadEvent.progress], which the native side sets to
  /// null whenever it does not know the total — and the file-size poller never
  /// knows the total, so it was null on every single event. The byte count was
  /// being sent the whole time and thrown away here, so onProgress was never
  /// called and task.receivedBytes stayed at 0.
  int? _bytesFrom(YoutubeNativeDownloadEvent event, int? knownSize) {
    final direct = event.receivedBytes;
    if (direct != null && direct > 0) return direct;
    final fraction = event.progress;
    if (fraction != null && knownSize != null && knownSize > 0) {
      return (fraction * knownSize).round();
    }
    return null;
  }
}

/// A native download failure carrying the normalized code from
/// YtDlpDownloader.classify, so DownloadManager can map it to a user-facing
/// message without string-matching a raw exception.
class NativeDownloadFailure implements Exception {
  final String code;
  final String message;

  const NativeDownloadFailure(this.code, this.message);

  /// True when a retry has a realistic chance of succeeding.
  bool get isRetryable =>
      code == 'HTTP_429' || code == 'NETWORK_ERROR' || code == 'DOWNLOAD_FAILED';

  /// User-facing text. Deliberately never the raw yt-dlp string.
  String get userMessage => switch (code) {
        'VIDEO_PRIVATE' => 'This video is private.',
        'VIDEO_AGE_RESTRICTED' => 'This video is age-restricted and cannot be downloaded.',
        'LOGIN_REQUIRED' => 'YouTube is asking this device to verify itself. Try again in a few minutes.',
        'VIDEO_GEO_RESTRICTED' => 'This video is not available in your region.',
        'VIDEO_UNAVAILABLE' => 'This video is no longer available.',
        'NO_FORMATS' => 'No downloadable format was available for this video.',
        'HTTP_403' => 'YouTube refused the download. Try a different quality.',
        'HTTP_429' => 'Too many requests. Wait a minute and try again.',
        'STORAGE_FULL' => 'Not enough free storage.',
        'STORAGE_UNAVAILABLE' => 'The download folder could not be written to.',
        'NETWORK_ERROR' => 'No connection.',
        'CANCELLED' => 'Cancelled.',
        _ => 'Download failed.',
      };

  @override
  String toString() => 'NativeDownloadFailure($code): $message';
}
