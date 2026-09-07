import 'package:flutter/foundation.dart';

/// Staged, greppable diagnostics for the YouTube download pipeline.
///
/// Every line is prefixed with a stage tag so `adb logcat | grep -E '\[YT\]|
/// \[DOWNLOAD\]|\[MUX\]|\[FILE\]'` gives the whole flow for one attempt in
/// order. The Kotlin side (YoutubeYtDlpPlugin, YtDlpDownloader) emits the same
/// tags through android.util.Log, so the two halves interleave correctly in a
/// single logcat capture.
///
/// SECRETS: [redact] strips anything URL-shaped and any token-like query
/// parameter before it reaches a log. Signed googlevideo URLs are credentials —
/// a full one in a bug report is enough for someone else to use it. Never call
/// `debugPrint` directly with a stream URL; route it through here.
///
/// This is diagnostic scaffolding for the current investigation. It compiles
/// out of release builds via [kDebugMode], so leaving it in place costs
/// nothing, but the verbose stages should be trimmed once the pipeline is
/// confirmed healthy.
class YtLog {
  YtLog._();

  /// Flip to false to silence the pipeline without removing call sites.
  static bool enabled = true;

  static final _urlPattern = RegExp(r'https?://\S+');
  static final _tokenParam = RegExp(
    r'([?&](?:signature|sig|pot|po_token|token|key|cookie|authuser|sid)=)[^&\s]*',
    caseSensitive: false,
  );

  /// yt-dlp extraction stages.
  static void yt(String message) => _write('YT', message);

  /// Transfer stages.
  static void download(String message) => _write('DOWNLOAD', message);

  /// Muxing stages.
  static void mux(String message) => _write('MUX', message);

  /// Which format playback actually chose. Debug builds only — these fire on
  /// every resolve and would be noise in release.
  static void play(String message) {
    if (kDebugMode) _write('YT-PLAY', message);
  }

  /// Player lifecycle: created, opened, disposed. Debug builds only.
  static void player(String message) {
    if (kDebugMode) _write('YT-PLAYER', message);
  }

  /// Buffering transitions. Debug builds only, and callers should log on state
  /// *change* rather than on every tick.
  static void buffer(String message) {
    if (kDebugMode) _write('YT-BUFFER', message);
  }

  /// Filesystem stages.
  static void file(String message) => _write('FILE', message);

  /// Failures. Always written, even when [enabled] is false, because a
  /// silenced logger must not hide errors.
  static void error(String stage, Object error, [StackTrace? stack]) {
    debugPrint('[$stage] ERROR: ${redact(error.toString())}');
    if (stack != null && kDebugMode) debugPrint(redact(stack.toString()));
  }

  /// Removes URLs and token-bearing parameters from [text].
  ///
  /// Order matters: token parameters are scrubbed first so that a URL which
  /// survives some future change to [_urlPattern] still cannot leak its
  /// signature.
  static String redact(String text) =>
      text.replaceAll(_tokenParam, r'$1<redacted>').replaceAll(_urlPattern, '<url>');

  /// Describes a URL without exposing it: host, and the googlevideo `c=`
  /// client that signed it, which is the part that actually matters when
  /// diagnosing a 403.
  static String describeUrl(String? url) {
    if (url == null || url.isEmpty) return 'none';
    try {
      final uri = Uri.parse(url);
      final client = uri.queryParameters['c'] ?? 'unknown';
      final expiry = uri.queryParameters['expire'];
      final expired = expiry == null
          ? ''
          : ', expired=${DateTime.now().millisecondsSinceEpoch ~/ 1000 > (int.tryParse(expiry) ?? 0)}';
      return '${uri.host} (c=$client$expired)';
    } catch (_) {
      return 'unparseable';
    }
  }

  static void _write(String stage, String message) {
    if (!enabled) return;
    debugPrint('[$stage] ${redact(message)}');
  }
}
