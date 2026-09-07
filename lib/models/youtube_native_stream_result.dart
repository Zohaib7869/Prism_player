/// Result of resolving a playback URL via native extraction.
///
/// Exact shape from the migration architecture doc §8:
/// `{videoUrl, audioUrl?, combined, quality, formatId, headers}`.
///
/// [combined] is true for a progressive format (video+audio already muxed —
/// only [videoUrl] is used for playback). When false, the format is
/// adaptive/DASH and [audioUrl] must also be set on the player
/// (`player.setAudioTrack(...)`) alongside [videoUrl] per §8's playback flow.
///
/// Never persisted — resolved fresh on every playback start (§8, spec item 16).
class YoutubeNativeStreamResult {
  final String videoUrl;
  final String? audioUrl;
  final bool combined;
  final String quality;
  final String formatId;
  final Map<String, String> headers;

  const YoutubeNativeStreamResult({
    required this.videoUrl,
    this.audioUrl,
    required this.combined,
    required this.quality,
    required this.formatId,
    this.headers = const {},
  });

  factory YoutubeNativeStreamResult.fromMap(Map<dynamic, dynamic> map) {
    return YoutubeNativeStreamResult(
      videoUrl: map['videoUrl']?.toString() ?? '',
      audioUrl: map['audioUrl'] as String?,
      combined: map['combined'] as bool? ?? true,
      quality: map['quality']?.toString() ?? '',
      formatId: map['formatId']?.toString() ?? '',
      headers: map['headers'] is Map
          ? Map<String, String>.from(map['headers'] as Map)
          : const {},
    );
  }

  @override
  String toString() =>
      'YoutubeNativeStreamResult(quality=$quality, combined=$combined, formatId=$formatId)';
}
