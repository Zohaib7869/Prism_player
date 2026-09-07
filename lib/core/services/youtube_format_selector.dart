import '../../models/youtube_native_format.dart';

/// Quality label <-> yt-dlp format selector, and format list -> available
/// quality labels. Architecture doc §15: "No hardcoded format IDs anywhere."
///
/// Selectors are yt-dlp's own selector syntax (`-f`), built dynamically from
/// a target height — never a literal format_id, since format IDs vary by
/// video and change over time as YouTube reshuffles itags.
class YoutubeFormatSelector {
  YoutubeFormatSelector._();

  static const String audioOnlyLabel = 'Audio only';
  static const String autoLabel = 'Auto';

  /// Standard YouTube adaptive heights, used to build the label list.
  /// Only labels actually present in [formats] are returned — this list is
  /// just the fixed set of resolutions yt-dlp/YouTube commonly publish, not
  /// a hardcoded format ID.
  static const List<int> _standardHeights = [2160, 1440, 1080, 720, 480, 360, 240, 144];

  /// Derives the available quality labels from a real format list, highest
  /// first. Includes [audioOnlyLabel] if any audio-only format exists.
  /// Returns an empty list if [formats] is empty.
  static List<String> availableQualityLabels(List<YoutubeNativeFormat> formats) {
    if (formats.isEmpty) return const [];

    final heights = formats
        .where((f) => f.hasVideo && f.height != null)
        .map((f) => f.height!)
        .toSet();

    final labels = <String>[
      for (final h in _standardHeights)
        if (heights.contains(h)) '${h}p',
      // Any non-standard heights present (e.g. an odd re-encode) still show up,
      // sorted after the standard ones, so nothing is silently dropped.
      for (final h in (heights.difference(_standardHeights.toSet()).toList()..sort((a, b) => b.compareTo(a))))
        '${h}p',
    ];

    final hasAudioOnly = formats.any((f) => f.hasAudio && !f.hasVideo);
    if (hasAudioOnly) labels.add(audioOnlyLabel);

    return labels;
  }

  /// Builds a yt-dlp `-f` selector string for a quality [label] returned by
  /// [availableQualityLabels] (or [autoLabel] / [audioOnlyLabel]).
  ///
  /// Always falls back gracefully (`/best[...]`) so a missing exact match
  /// still resolves to *something* playable rather than erroring — yt-dlp
  /// evaluates selectors left-to-right and uses the first that resolves.
  static String selectorForLabel(String label) {
    if (label == audioOnlyLabel) {
      return 'bestaudio[acodec^=mp4a]/bestaudio[ext=m4a]/bestaudio/best';
    }
    if (label == autoLabel) {
      return 'bestvideo[vcodec^=avc1]+bestaudio[acodec^=mp4a]/'
          'bestvideo+bestaudio/best';
    }

    final height = _parseHeight(label);
    if (height == null) {
      // Unrecognized label — safest fallback is "best available", never a
      // hardcoded format id.
      return 'bestvideo+bestaudio/best';
    }
    // H.264 + AAC are requested first because they are the only combination
    // with guaranteed hardware decoding on Android. Left unconstrained this
    // resolved to itag 398 (AV1) + 251 (Opus): AV1 has no hardware decoder on
    // most mid-range devices, so mpv falls back to software decode and the
    // video stutters. The unconstrained variants stay as fallbacks so a video
    // published only in AV1 still plays rather than failing outright.
    return 'bestvideo[vcodec^=avc1][height<=$height]+bestaudio[acodec^=mp4a]/'
        'bestvideo[height<=$height]+bestaudio/'
        'best[height<=$height]';
  }

  static int? _parseHeight(String label) {
    final match = RegExp(r'^(\d+)p$').firstMatch(label);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }
}
