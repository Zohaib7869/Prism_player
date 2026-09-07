/// A single format entry as returned by native yt-dlp extraction
/// (`info["formats"]`, sanitized). Mirrors the fields the migration
/// architecture doc (§6/§8) says are needed for the quality picker and
/// playback headers — nothing hardcoded, no assumed format IDs.
///
/// Not persisted (§8: stream URLs are resolved fresh on every play, never
/// stored in Hive) — this is a transient, in-memory shape only.
class YoutubeNativeFormat {
  final String formatId;
  final String? ext;
  final int? height;
  final int? width;
  final double? fps;
  final String? vcodec;
  final String? acodec;
  final double? abr; // audio bitrate, kbps
  final double? vbr; // video bitrate, kbps
  final double? tbr; // total bitrate, kbps
  final int? filesize;
  final int? filesizeApprox;
  final String? formatNote;
  final Map<String, String> httpHeaders;

  const YoutubeNativeFormat({
    required this.formatId,
    this.ext,
    this.height,
    this.width,
    this.fps,
    this.vcodec,
    this.acodec,
    this.abr,
    this.vbr,
    this.tbr,
    this.filesize,
    this.filesizeApprox,
    this.formatNote,
    this.httpHeaders = const {},
  });

  /// yt-dlp convention: vcodec/acodec == "none" means that stream is absent.
  bool get hasVideo => vcodec != null && vcodec != 'none';
  bool get hasAudio => acodec != null && acodec != 'none';

  factory YoutubeNativeFormat.fromMap(Map<dynamic, dynamic> map) {
    return YoutubeNativeFormat(
      formatId: map['formatId']?.toString() ?? map['format_id']?.toString() ?? '',
      ext: map['ext'] as String?,
      height: (map['height'] as num?)?.toInt(),
      width: (map['width'] as num?)?.toInt(),
      fps: (map['fps'] as num?)?.toDouble(),
      vcodec: map['vcodec'] as String?,
      acodec: map['acodec'] as String?,
      abr: (map['abr'] as num?)?.toDouble(),
      vbr: (map['vbr'] as num?)?.toDouble(),
      tbr: (map['tbr'] as num?)?.toDouble(),
      filesize: (map['filesize'] as num?)?.toInt(),
      filesizeApprox: (map['filesizeApprox'] as num?)?.toInt() ??
          (map['filesize_approx'] as num?)?.toInt(),
      formatNote: (map['formatNote'] ?? map['format_note']) as String?,
      httpHeaders: (map['httpHeaders'] ?? map['http_headers']) is Map
          ? Map<String, String>.from(
              (map['httpHeaders'] ?? map['http_headers']) as Map)
          : const {},
    );
  }

  @override
  String toString() =>
      'YoutubeNativeFormat($formatId, ${height ?? '?'}p, video=$hasVideo, audio=$hasAudio)';
}
