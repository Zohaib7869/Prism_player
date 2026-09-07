/// Parses YouTube links into the `videoId` the rest of the app already speaks.
///
/// Everything downstream — [YoutubeService], [DownloadOptionsSheet],
/// [DownloadManager] — is already keyed on a bare 11-character video id. Until
/// now the only thing that produced one was a search result, so a link the user
/// pasted or shared into the app had no way in. This class is that way in, and
/// deliberately nothing more: it does no network work and knows nothing about
/// formats, so it is cheap enough to run on every clipboard change and safe to
/// call from an intent handler before the Flutter engine has warmed up.
library;

/// A link successfully recognised as YouTube.
class YoutubeLink {
  /// The 11-character video id.
  final String videoId;

  /// Playlist id from `list=`, when the link pointed at a video *in* a
  /// playlist. Kept because it is free to extract here and impossible to
  /// recover later, even though nothing consumes it yet.
  final String? playlistId;

  /// Start offset from `t=` / `start=`, normalised to seconds. Feeds the
  /// player's resume position when a timestamped link is opened.
  final Duration? startAt;

  const YoutubeLink({
    required this.videoId,
    this.playlistId,
    this.startAt,
  });

  @override
  String toString() =>
      'YoutubeLink($videoId${playlistId != null ? ', list=$playlistId' : ''}'
      '${startAt != null ? ', t=${startAt!.inSeconds}s' : ''})';

  @override
  bool operator ==(Object other) =>
      other is YoutubeLink &&
      other.videoId == videoId &&
      other.playlistId == playlistId &&
      other.startAt == startAt;

  @override
  int get hashCode => Object.hash(videoId, playlistId, startAt);
}

class YoutubeUrlParser {
  YoutubeUrlParser._();

  /// Hosts we accept. `youtube-nocookie.com` serves the privacy-preserving
  /// embed domain and `youtu.be` is the short form, where the id is the path
  /// rather than a query parameter.
  static const _hosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'music.youtube.com',
    'gaming.youtube.com',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
    'youtu.be',
    'www.youtu.be',
  };

  /// Path prefixes that carry the id as the next segment.
  static const _idBearingSegments = {'shorts', 'live', 'embed', 'v', 'e'};

  /// A YouTube id is exactly 11 characters of the URL-safe base64 alphabet.
  /// The lookarounds stop a 12+ character token from yielding a false match on
  /// its first 11 characters, which is what makes [findFirstIn] safe to run
  /// over arbitrary shared text.
  static final _idPattern =
      RegExp(r'(?<![A-Za-z0-9_-])([A-Za-z0-9_-]{11})(?![A-Za-z0-9_-])');

  /// `1h2m3s`, `2m10s`, `90s`, or a bare `90`.
  static final _timestampPattern =
      RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$', caseSensitive: false);

  /// Parses a single URL. Returns null when [input] is not a YouTube video
  /// link — including when it is a valid YouTube *channel* or *playlist* link,
  /// since neither resolves to something this app can play or download.
  static YoutubeLink? parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // A bare id, which is what a user pasting from a "copy video id" tool ends
    // up with. Checked first so it doesn't have to survive Uri parsing.
    if (_idPattern.firstMatch(trimmed)?.group(1) == trimmed) {
      return YoutubeLink(videoId: trimmed);
    }

    // Uri.parse tolerates a missing scheme but then puts everything in `path`
    // and leaves `host` empty, so host matching silently fails on
    // "youtu.be/xyz". Adding the scheme up front is cheaper than special-casing
    // that afterwards.
    final withScheme =
        trimmed.startsWith(RegExp(r'https?://', caseSensitive: false))
            ? trimmed
            : 'https://$trimmed';

    final Uri uri;
    try {
      uri = Uri.parse(withScheme);
    } on FormatException {
      return null;
    }

    if (!_hosts.contains(uri.host.toLowerCase())) return null;

    final segments =
        uri.pathSegments.where((s) => s.isNotEmpty).toList(growable: false);

    String? id;

    if (uri.host.toLowerCase().endsWith('youtu.be')) {
      // Short form: the id is the whole path.
      id = segments.isNotEmpty ? segments.first : null;
    } else if (uri.queryParameters.containsKey('v')) {
      // Canonical watch URL.
      id = uri.queryParameters['v'];
    } else if (segments.length >= 2 &&
        _idBearingSegments.contains(segments.first.toLowerCase())) {
      // /shorts/ID, /live/ID, /embed/ID, /v/ID.
      id = segments[1];
    } else if (uri.path.toLowerCase().contains('attribution_link')) {
      // Mobile share sheets sometimes emit an attribution wrapper whose `u`
      // parameter holds a percent-encoded relative watch URL.
      final inner = uri.queryParameters['u'];
      if (inner != null) return parse('https://www.youtube.com$inner');
    }

    if (id == null) return null;

    // Strip anything the id picked up from a malformed path, then validate.
    final match = _idPattern.firstMatch(id);
    if (match == null || match.group(1) != id) return null;

    return YoutubeLink(
      videoId: id,
      playlistId: uri.queryParameters['list'],
      startAt: _parseTimestamp(
        uri.queryParameters['t'] ?? uri.queryParameters['start'],
      ),
    );
  }

  /// Finds the first YouTube link inside free text.
  ///
  /// This is the one that matters for `ACTION_SEND`: the YouTube app shares
  /// "Video title\nhttps://youtu.be/abc" rather than a bare URL, so feeding the
  /// whole payload to [parse] would fail on every real share.
  static YoutubeLink? findFirstIn(String text) {
    for (final match
        in RegExp(r'\S*(?:youtube\.com|youtu\.be|youtube-nocookie\.com)\S*',
                caseSensitive: false)
            .allMatches(text)) {
      // Trailing punctuation from prose ("watch this: https://youtu.be/abc.")
      // would otherwise be swallowed into the id and fail validation.
      final candidate = match.group(0)!.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
      final link = parse(candidate);
      if (link != null) return link;
    }
    return null;
  }

  /// True when [text] contains something worth offering to open. Cheap enough
  /// for a clipboard poll on resume.
  static bool looksLikeYoutube(String text) => findFirstIn(text) != null;

  static Duration? _parseTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final m = _timestampPattern.firstMatch(raw);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '') ?? 0;
    final min = int.tryParse(m.group(2) ?? '') ?? 0;
    final s = int.tryParse(m.group(3) ?? '') ?? 0;
    if (h == 0 && min == 0 && s == 0) return null;
    return Duration(hours: h, minutes: min, seconds: s);
  }
}
