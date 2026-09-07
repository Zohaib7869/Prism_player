import 'package:flutter/services.dart';

import '../../models/youtube_native_download_event.dart';
import '../../models/youtube_native_info.dart';
import '../../models/youtube_native_stream_result.dart';

/// Normalized error codes from architecture doc §11. Every [PlatformException]
/// thrown by native yt-dlp code uses one of these as its `code`.
enum YoutubeNativeErrorCode {
  ytdlpInitFailed,
  ytdlpUnavailable,
  youtubeNotFound,
  videoPrivate,
  videoUnavailable,
  videoAgeRestricted,
  videoGeoRestricted,
  formatNotAvailable,
  extractionError,
  networkError,
  http403,
  http429,
  downloadError,
  cancelled,
  storageError,
  tlsFingerprintRequired,
  unknown;

  static YoutubeNativeErrorCode fromWireCode(String? code) {
    switch (code) {
      case 'YTDLP_INIT_FAILED':
        return YoutubeNativeErrorCode.ytdlpInitFailed;
      case 'YTDLP_UNAVAILABLE':
        return YoutubeNativeErrorCode.ytdlpUnavailable;
      case 'YOUTUBE_NOT_FOUND':
        return YoutubeNativeErrorCode.youtubeNotFound;
      case 'VIDEO_PRIVATE':
        return YoutubeNativeErrorCode.videoPrivate;
      case 'VIDEO_UNAVAILABLE':
        return YoutubeNativeErrorCode.videoUnavailable;
      case 'VIDEO_AGE_RESTRICTED':
        return YoutubeNativeErrorCode.videoAgeRestricted;
      case 'VIDEO_GEO_RESTRICTED':
        return YoutubeNativeErrorCode.videoGeoRestricted;
      case 'FORMAT_NOT_AVAILABLE':
        return YoutubeNativeErrorCode.formatNotAvailable;
      case 'EXTRACTION_ERROR':
        return YoutubeNativeErrorCode.extractionError;
      case 'NETWORK_ERROR':
        return YoutubeNativeErrorCode.networkError;
      case 'HTTP_403':
        return YoutubeNativeErrorCode.http403;
      case 'HTTP_429':
        return YoutubeNativeErrorCode.http429;
      case 'DOWNLOAD_ERROR':
        return YoutubeNativeErrorCode.downloadError;
      case 'CANCELLED':
        return YoutubeNativeErrorCode.cancelled;
      case 'STORAGE_ERROR':
        return YoutubeNativeErrorCode.storageError;
      case 'TLS_FINGERPRINT_REQUIRED':
        return YoutubeNativeErrorCode.tlsFingerprintRequired;
      default:
        return YoutubeNativeErrorCode.unknown;
    }
  }
}

/// Thrown by [YoutubeNativeService] methods on any native failure, wrapping
/// the raw [PlatformException] with a typed [code] from §11.
class YoutubeNativeException implements Exception {
  final YoutubeNativeErrorCode code;
  final String message;
  final PlatformException cause;

  YoutubeNativeException(this.cause)
      : code = YoutubeNativeErrorCode.fromWireCode(cause.code),
        message = cause.message ?? cause.code;

  @override
  String toString() => 'YoutubeNativeException($code, $message)';
}

/// Thin Dart wrapper around the native `com.prismplayer.app/ytdlp` channel
/// and its `com.prismplayer.app/ytdlp_events` EventChannel — the only
/// MethodChannel/EventChannel consumer for the yt-dlp migration (§15).
///
/// [isAvailable], [getVersion], [extractDiagnostics], [getInfo], and
/// [getStreamUrls] are implemented natively today (spikes 1+2, steps 4–5).
/// [download] and [cancelDownload] still define the step-6 contract for a
/// native download *job* — not needed for the current fix, since downloads
/// go through the existing SegmentedDownloader using the URLs [getStreamUrls]
/// resolves. Calling either before that lands throws a
/// [MissingPluginException], which is expected.
class YoutubeNativeService {
  static const _channel = MethodChannel('com.prismplayer.app/ytdlp');
  static const _eventChannel = EventChannel('com.prismplayer.app/ytdlp_events');

  Future<bool> isAvailable() async {
    final result = await _channel.invokeMethod<bool>('is_available');
    return result ?? false;
  }

  /// Returns the bundled yt-dlp version string, or throws a
  /// [YoutubeNativeException] if native init hasn't succeeded or the
  /// Chaquopy call itself failed.
  Future<String?> getVersion() => _invoke(() => _channel.invokeMethod<String>('get_version'));

  /// Spike 2 diagnostic only — runs yt_dlp.extract_info(download=false) for
  /// [url] and returns a small map: {title, durationSeconds, extractor,
  /// formatCount}. Superseded by [getInfo] for real use; kept as a
  /// lightweight on-device sanity check.
  Future<Map<dynamic, dynamic>?> extractDiagnostics(String url) => _invoke(
        () => _channel.invokeMethod<Map<dynamic, dynamic>>(
          'extract_diagnostics',
          {'url': url},
        ),
      );

  /// STEP 4 — implemented natively. Full metadata + format list for the
  /// quality picker (§4/§6 "Format discovery"). Throws
  /// [YoutubeNativeException] on failure (see [YoutubeNativeErrorCode] for
  /// the normalized code set this can surface).
  Future<YoutubeNativeInfo> getInfo(String url) async {
    final map = await _invoke(
      () => _channel.invokeMethod<Map<dynamic, dynamic>>('get_info', {'url': url}),
    );
    return YoutubeNativeInfo.fromMap(map ?? const {});
  }

  /// STEP 5 — implemented natively. Resolves a playback URL for [url] at
  /// the given yt-dlp [formatSelector]
  /// (from [YoutubeFormatSelector.selectorForLabel]) — architecture doc §8.
  /// Never cache the result; call again on every playback start.
  Future<YoutubeNativeStreamResult> getStreamUrls(String url, String formatSelector) async {
    final map = await _invoke(
      () => _channel.invokeMethod<Map<dynamic, dynamic>>('get_stream_urls', {
        'url': url,
        'formatSelector': formatSelector,
      }),
    );
    return YoutubeNativeStreamResult.fromMap(map ?? const {});
  }

  /// STEP 6 CONTRACT — not yet implemented natively.
  /// Starts a native download job (§9). Progress/completion arrive via
  /// [downloadEvents], keyed by [downloadId] — this call itself only
  /// confirms the job was accepted, it does not await completion.
  Future<void> download({
    required String url,
    required String formatSelector,
    required String outputTemplate,
    required String downloadId,
  }) =>
      _invokeVoid(
        () => _channel.invokeMethod<void>('download', {
          'url': url,
          'formatSelector': formatSelector,
          'outputTemplate': outputTemplate,
          'downloadId': downloadId,
        }),
      );

  /// STEP 6 CONTRACT — not yet implemented natively.
  /// Best-effort cancel per §10 — marks the job cancelled and stops event
  /// forwarding; it cannot interrupt an in-flight yt-dlp download.
  Future<void> cancelDownload(String downloadId) => _invokeVoid(
        () => _channel.invokeMethod<void>('cancel_download', {'downloadId': downloadId}),
      );

  /// STEP 6 CONTRACT — not yet implemented natively.
  /// Stream of all download job events across the app lifetime; callers
  /// filter by [YoutubeNativeDownloadEvent.downloadId].
  Stream<YoutubeNativeDownloadEvent> get downloadEvents => _eventChannel
      .receiveBroadcastStream()
      .map((event) => YoutubeNativeDownloadEvent.fromMap(event as Map));

  Future<T> _invoke<T>(Future<T?> Function() call) async {
    try {
      final result = await call();
      if (result == null) {
        throw StateError('Native call returned null');
      }
      return result;
    } on PlatformException catch (e) {
      throw YoutubeNativeException(e);
    }
  }

  Future<void> _invokeVoid(Future<void> Function() call) async {
    try {
      await call();
    } on PlatformException catch (e) {
      throw YoutubeNativeException(e);
    }
  }
}

