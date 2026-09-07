import '../../models/youtube_native_format.dart';
import 'youtube_format_selector.dart';
import 'youtube_native_service.dart';
import 'youtube_service.dart';

/// Bridges the native yt-dlp extraction path (YoutubeNativeService) to the
/// existing YoutubeDownloadOption model that DownloadOptionsSheet and
/// DownloadManager already know how to display/queue.
///
/// Why this exists: youtube_explode_dart's adaptive stream URLs are the ones
/// YouTube has been refusing with 403s (see download_manager.dart's history).
/// yt-dlp's plain free-build extract_info chain gets past that bot-check
/// (verified on-device, spike 2) — so downloads resolved through here should
/// actually succeed at the quality the user picked instead of silently
/// collapsing to whatever progressive stream happens to survive.
class YoutubeNativeDownloadResolver {
  final YoutubeNativeService native;
  YoutubeNativeDownloadResolver(this.native);

  static String watchUrlFor(String videoId) => 'https://www.youtube.com/watch?v=$videoId';

  /// Best-effort catalog fetch for the download sheet's list: real quality
  /// labels for this video, with no stream URLs resolved yet (that only
  /// happens once, for whichever single quality the user actually taps —
  /// see [resolve] — matching the "resolve fresh, only when needed" rule
  /// from the migration architecture doc).
  Future<List<YoutubeNativeFormat>> listFormats(String videoId) async {
    final info = await native.getInfo(watchUrlFor(videoId));
    return info.formats;
  }

  /// Placeholder options for the sheet to render immediately from
  /// [listFormats] — label, audioOnly flag, and a rough size estimate where
  /// yt-dlp's metadata has one. No URLs yet; [resolve] fills those in only
  /// for the one option the user selects.
  List<YoutubeDownloadOption> buildPlaceholderOptions(List<YoutubeNativeFormat> formats) {
    final labels = YoutubeFormatSelector.availableQualityLabels(formats);
    final bestAudio = _bestAudioFormat(formats);

    return [
      for (final label in labels)
        if (label != YoutubeFormatSelector.audioOnlyLabel)
          YoutubeDownloadOption(
            label: label,
            audioOnly: false,
            audioUrl: '',
            videoBytes: _bestVideoFormatForLabel(formats, label)?.bestSize ?? 0,
            audioBytes: bestAudio?.bestSize ?? 0,
            nativeFormatSelector: YoutubeFormatSelector.selectorForLabel(label),
          ),
      if (bestAudio != null)
        YoutubeDownloadOption(
          label: '${(bestAudio.abr ?? 0).round()} kbps',
          audioOnly: true,
          audioUrl: '',
          audioBytes: bestAudio.bestSize,
          nativeFormatSelector:
              YoutubeFormatSelector.selectorForLabel(YoutubeFormatSelector.audioOnlyLabel),
        ),
    ];
  }

  /// Resolves real, authorized URLs for one placeholder option (called once,
  /// right when the user taps it — see download_options_sheet.dart). Never
  /// cache the result: URLs are short-lived and signed per-request.
  Future<YoutubeDownloadOption> resolve(String videoId, YoutubeDownloadOption placeholder) async {
    final selector = placeholder.nativeFormatSelector!;
    final res = await native.getStreamUrls(watchUrlFor(videoId), selector);

    // A genuine adaptive video+audio pair is the only case with two distinct
    // URLs to fetch and mux; everything else (progressive, or a single
    // audio-only pick) is one URL, which — matching the convention the rest
    // of the download pipeline already uses for "no mux needed" — goes in
    // audioUrl with videoUrl left null.
    final isAdaptivePair = !placeholder.audioOnly && !res.combined && res.audioUrl != null;

    return YoutubeDownloadOption(
      label: placeholder.label,
      audioOnly: placeholder.audioOnly,
      videoUrl: isAdaptivePair ? res.videoUrl : null,
      audioUrl: isAdaptivePair ? res.audioUrl! : res.videoUrl,
      videoBytes: isAdaptivePair ? placeholder.videoBytes : 0,
      audioBytes: isAdaptivePair ? placeholder.audioBytes : (placeholder.videoBytes + placeholder.audioBytes),
      headers: res.headers,
      nativeFormatSelector: selector,
    );
  }

  YoutubeNativeFormat? _bestAudioFormat(List<YoutubeNativeFormat> formats) {
    final audioOnly = formats.where((f) => f.hasAudio && !f.hasVideo).toList()
      ..sort((a, b) => (b.abr ?? 0).compareTo(a.abr ?? 0));
    return audioOnly.isEmpty ? null : audioOnly.first;
  }

  YoutubeNativeFormat? _bestVideoFormatForLabel(List<YoutubeNativeFormat> formats, String label) {
    final height = int.tryParse(label.replaceAll('p', ''));
    if (height == null) return null;
    final matches = formats.where((f) => f.hasVideo && f.height == height).toList()
      ..sort((a, b) => (b.tbr ?? 0).compareTo(a.tbr ?? 0));
    return matches.isEmpty ? null : matches.first;
  }
}

extension on YoutubeNativeFormat {
  int get bestSize => filesize ?? filesizeApprox ?? 0;
}
