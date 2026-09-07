/// One event from the `com.prismplayer.app/ytdlp_events` EventChannel
/// (architecture doc §9). `DownloadManager` maps these onto `DownloadStatus`.
enum YoutubeNativeDownloadEventType { started, progress, completed, failed, cancelled }

class YoutubeNativeDownloadEvent {
  final String downloadId;
  final YoutubeNativeDownloadEventType type;

  /// 0.0–1.0, only meaningful for [YoutubeNativeDownloadEventType.progress].
  final double? progress;
  final int? etaSeconds;

  /// Bytes written so far. The native side always sends this; [progress] is
  /// only populated when a total was known, which for a yt-dlp transfer it
  /// usually is not. Prefer this over [progress].
  final int? receivedBytes;

  /// Total size when the native side knows it, else null/0.
  final int? totalBytes;

  /// Final file path, only set on [YoutubeNativeDownloadEventType.completed].
  final String? outputPath;

  /// Normalized code from architecture doc §11 (e.g. HTTP_403,
  /// TLS_FINGERPRINT_REQUIRED), only set on
  /// [YoutubeNativeDownloadEventType.failed].
  final String? errorCode;
  final String? errorMessage;

  const YoutubeNativeDownloadEvent({
    required this.downloadId,
    required this.type,
    this.progress,
    this.etaSeconds,
    this.receivedBytes,
    this.totalBytes,
    this.outputPath,
    this.errorCode,
    this.errorMessage,
  });

  factory YoutubeNativeDownloadEvent.fromMap(Map<dynamic, dynamic> map) {
    return YoutubeNativeDownloadEvent(
      downloadId: map['downloadId']?.toString() ?? '',
      type: _parseType(map['type']?.toString()),
      progress: (map['progress'] as num?)?.toDouble(),
      etaSeconds: (map['etaSeconds'] as num?)?.toInt(),
      receivedBytes: (map['receivedBytes'] as num?)?.toInt(),
      totalBytes: (map['totalBytes'] as num?)?.toInt(),
      outputPath: map['outputPath'] as String?,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }

  static YoutubeNativeDownloadEventType _parseType(String? raw) {
    switch (raw) {
      case 'started':
        return YoutubeNativeDownloadEventType.started;
      case 'progress':
        return YoutubeNativeDownloadEventType.progress;
      case 'completed':
        return YoutubeNativeDownloadEventType.completed;
      case 'cancelled':
        return YoutubeNativeDownloadEventType.cancelled;
      case 'failed':
      default:
        return YoutubeNativeDownloadEventType.failed;
    }
  }

  @override
  String toString() =>
      'YoutubeNativeDownloadEvent($downloadId, $type, progress=$progress)';
}
