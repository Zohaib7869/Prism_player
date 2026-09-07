import 'youtube_native_format.dart';

/// Normalized video metadata from native extraction (`extract_info` +
/// `sanitize_info`, reduced to what the app needs — architecture doc §6:
/// "Normalisation happens in Kotlin, once ... Raw logs never cross.").
///
/// Broader than the spike-2 diagnostic map: this is the real contract used
/// by the format picker (§4 "Format discovery") and download quality sheet.
class YoutubeNativeInfo {
  final String id;
  final String title;
  final double? durationSeconds;
  final String? thumbnailUrl;
  final String? uploader;
  final String? extractor;
  final List<YoutubeNativeFormat> formats;

  const YoutubeNativeInfo({
    required this.id,
    required this.title,
    this.durationSeconds,
    this.thumbnailUrl,
    this.uploader,
    this.extractor,
    this.formats = const [],
  });

  factory YoutubeNativeInfo.fromMap(Map<dynamic, dynamic> map) {
    final rawFormats = map['formats'];
    return YoutubeNativeInfo(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ??
          (map['duration'] as num?)?.toDouble(),
      thumbnailUrl: (map['thumbnailUrl'] ?? map['thumbnail']) as String?,
      uploader: map['uploader'] as String?,
      extractor: map['extractor'] as String?,
      formats: rawFormats is List
          ? rawFormats
              .whereType<Map>()
              .map((f) => YoutubeNativeFormat.fromMap(f))
              .toList()
          : const [],
    );
  }

  @override
  String toString() =>
      'YoutubeNativeInfo($id, "$title", ${formats.length} formats)';
}
