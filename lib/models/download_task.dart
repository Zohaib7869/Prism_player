import 'package:hive/hive.dart';

/// Lifecycle of a single download.
///
/// [muxing] is its own state rather than a tail of [running] because it is the
/// one phase with no network progress to report — the UI shows an
/// indeterminate "Merging…" bar instead of a percentage, and cancelling during
/// it has to wait for the native muxer rather than just dropping sockets.
enum DownloadStatus { queued, running, muxing, paused, completed, failed }

/// One row per requested download. Kept in its own Hive box (typeId 5) so a
/// download survives the app being killed mid-transfer: the part files on disk
/// plus [receivedBytes] are enough for [SegmentedDownloader] to pick up exactly
/// where it stopped.
class DownloadTask extends HiveObject {
  final String id;
  final String videoId;
  String title;
  final String? author;
  final String? thumbnailUrl;

  /// True for "Music"/audio-only downloads, which skip the mux step entirely —
  /// YouTube's audio-only streams are already a valid standalone .m4a.
  final bool isAudioOnly;

  /// Human label shown in the UI: "1080p", "128 kbps", ... Mutable because a
  /// 403-driven progressive fallback (see DownloadManager._run) can silently
  /// drop the actual delivered quality below what was originally requested —
  /// the label needs to follow that so the UI doesn't keep claiming 720p for
  /// a file that is actually 360p.
  String qualityLabel;

  /// Video-only stream URL. Null when [isAudioOnly].
  String? videoUrl;
  String audioUrl;

  /// Where the finished file lands.
  final String outputPath;

  int videoBytes;
  int audioBytes;
  int receivedBytes;

  int statusIndex;
  String? errorMessage;

  final int createdAtMs;
  int completedAtMs;
  int durationMs;

  /// Forces [isStale] to return true regardless of creation time. Used when a 
  /// download fails with a 403, so the retry fetches fresh authorized URLs.
  bool _isStaleOverride = false;

  /// Request headers [videoUrl]/[audioUrl] were signed/authorized for. Set
  /// only for downloads resolved via the native yt-dlp path — null means
  /// "use the legacy per-client headers from YoutubeService.streamHeadersFor".
  Map<String, String>? headers;

  /// yt-dlp's `-f` selector string that produced this task's URLs, e.g.
  /// `"bestvideo[height<=720]+bestaudio/best[height<=720]"`. Null for tasks
  /// from the legacy youtube_explode_dart path. When set, a stale/failed
  /// retry re-resolves through YoutubeNativeService.getStreamUrls with this
  /// same selector instead of the old manifest-based refresh.
  String? nativeFormatSelector;

  DownloadTask({
    required this.id,
    required this.videoId,
    required this.title,
    required this.outputPath,
    required this.qualityLabel,
    required this.audioUrl,
    required this.createdAtMs,
    this.author,
    this.thumbnailUrl,
    this.isAudioOnly = false,
    this.videoUrl,
    this.videoBytes = 0,
    this.audioBytes = 0,
    this.receivedBytes = 0,
    this.statusIndex = 0,
    this.errorMessage,
    this.completedAtMs = 0,
    this.durationMs = 0,
    this.headers,
    this.nativeFormatSelector,
  });

  DownloadStatus get status => DownloadStatus.values[statusIndex.clamp(0, DownloadStatus.values.length - 1)];
  set status(DownloadStatus value) => statusIndex = value.index;

  int get totalBytes => videoBytes + audioBytes;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  /// Everything that belongs in the "Downloading" tab — including failures and
  /// pauses, which the user still needs to see in order to retry or clear them.
  bool get isPending => status != DownloadStatus.completed;

  /// Stream URLs are signed and expire after a few hours. A paused download
  /// resumed the next day has to re-resolve them before it can continue.
  bool get isStale => _isStaleOverride || DateTime.now().millisecondsSinceEpoch - createdAtMs > 3 * 60 * 60 * 1000;
  
  /// Allows forcing a refresh on 403 errors.
  set isStale(bool value) => _isStaleOverride = value;
}

class DownloadTaskAdapter extends TypeAdapter<DownloadTask> {
  @override
  final int typeId = 5;

  @override
  DownloadTask read(BinaryReader reader) {
    final numFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadTask(
      id: fields[0] as String,
      videoId: fields[1] as String,
      title: fields[2] as String,
      author: fields[3] as String?,
      thumbnailUrl: fields[4] as String?,
      isAudioOnly: fields[5] as bool,
      qualityLabel: fields[6] as String,
      videoUrl: fields[7] as String?,
      audioUrl: fields[8] as String,
      outputPath: fields[9] as String,
      videoBytes: fields[10] as int,
      audioBytes: fields[11] as int,
      receivedBytes: fields[12] as int,
      statusIndex: fields[13] as int,
      errorMessage: fields[14] as String?,
      createdAtMs: fields[15] as int,
      completedAtMs: fields[16] as int,
      durationMs: fields[17] as int,
      // Fields 18/19 are absent on records written before the native yt-dlp
      // download path existed — `fields[18]` on a 18-field-old record is
      // just a missing map key (null), not a decode error, so old queued/
      // paused/completed downloads keep loading fine.
      headers: (fields[18] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())),
      nativeFormatSelector: fields[19] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadTask obj) {
    writer
      ..writeByte(20)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.videoId)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.author)
      ..writeByte(4)
      ..write(obj.thumbnailUrl)
      ..writeByte(5)
      ..write(obj.isAudioOnly)
      ..writeByte(6)
      ..write(obj.qualityLabel)
      ..writeByte(7)
      ..write(obj.videoUrl)
      ..writeByte(8)
      ..write(obj.audioUrl)
      ..writeByte(9)
      ..write(obj.outputPath)
      ..writeByte(10)
      ..write(obj.videoBytes)
      ..writeByte(11)
      ..write(obj.audioBytes)
      ..writeByte(12)
      ..write(obj.receivedBytes)
      ..writeByte(13)
      ..write(obj.statusIndex)
      ..writeByte(14)
      ..write(obj.errorMessage)
      ..writeByte(15)
      ..write(obj.createdAtMs)
      ..writeByte(16)
      ..write(obj.completedAtMs)
      ..writeByte(17)
      ..write(obj.durationMs)
      ..writeByte(18)
      ..write(obj.headers)
      ..writeByte(19)
      ..write(obj.nativeFormatSelector);
  }
}