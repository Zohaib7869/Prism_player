/// A single, user-facing vocabulary for everything that can go wrong on the
/// YouTube path.
///
/// Today [YoutubeNativeService._invoke] wraps a `PlatformException` into a
/// `YoutubeNativeException` and the raw yt-dlp string reaches the UI, so users
/// see things like "ERROR: [youtube] abc: Sign in to confirm you're not a bot.
/// Use --cookies-from-browser". That string is exactly what a maintainer wants
/// in a log and exactly what a user cannot act on.
///
/// This splits the two. [YoutubeErrorKind] is the small closed set the UI
/// switches on; [YoutubeFailure.diagnostic] keeps the original text for logs
/// and bug reports and is never rendered.
library;

enum YoutubeErrorKind {
  /// The text wasn't a YouTube video link at all.
  invalidUrl,

  /// Deleted, or the id doesn't exist.
  videoUnavailable,

  /// Exists but the owner made it private.
  privateVideo,

  /// Age-gated. Distinct from [signInRequired] because the remedy differs and
  /// there is no remedy we can offer in-app.
  ageRestricted,

  /// YouTube's bot check fired, or the video needs an account.
  signInRequired,

  /// Blocked in this country.
  geoBlocked,

  /// A live broadcast still in progress. Downloading these needs fragment
  /// handling the app doesn't do.
  liveNotSupported,

  /// Resolved, but every format was something we can't play or mux.
  unsupportedStream,

  /// yt-dlp ran and failed in a way that suggests YouTube changed something.
  /// The actionable difference from [temporaryYoutubeError] is that retrying
  /// won't help — the extractor needs updating.
  extractorOutdated,

  /// A 5xx, a rate limit, or a transient extractor failure. Retry is sensible.
  temporaryYoutubeError,

  /// Resolution failed for a reason we couldn't classify.
  extractionFailed,

  /// No usable connection.
  networkUnavailable,

  /// The transfer itself failed after resolution succeeded.
  downloadFailed,

  /// Target directory is gone or unwritable (SD card ejected, scoped-storage
  /// permission revoked).
  storageUnavailable,

  /// Not enough free space for the selected format.
  insufficientStorage,

  /// User cancelled. Modelled as a failure so the download pipeline has one
  /// terminal type, but the UI should stay silent for it.
  cancelled,
}

/// A classified failure. Construct via [YoutubeFailure.from] rather than
/// directly, so classification stays in one place.
class YoutubeFailure implements Exception {
  final YoutubeErrorKind kind;

  /// The original exception text. For logs and "copy diagnostics" only —
  /// never put this in front of a user.
  final String? diagnostic;

  final Object? cause;

  const YoutubeFailure(this.kind, {this.diagnostic, this.cause});

  /// Whether offering a Retry button makes sense.
  bool get isRetryable =>
      kind == YoutubeErrorKind.temporaryYoutubeError ||
      kind == YoutubeErrorKind.networkUnavailable ||
      kind == YoutubeErrorKind.downloadFailed;

  /// Whether the UI should say anything at all.
  bool get isSilent => kind == YoutubeErrorKind.cancelled;

  @override
  String toString() => 'YoutubeFailure(${kind.name}): ${diagnostic ?? ''}';

  /// Classifies an arbitrary error into the taxonomy.
  ///
  /// The matching is deliberately substring-based on yt-dlp's English output.
  /// That is fragile, and it is still better than what happens now: an
  /// unmatched message falls through to [YoutubeErrorKind.extractionFailed]
  /// and the detail survives in [diagnostic], so a new upstream wording
  /// degrades to a generic message rather than a crash or a leaked stack.
  factory YoutubeFailure.from(Object error, {String? messageOverride}) {
    final raw = messageOverride ?? error.toString();
    final s = raw.toLowerCase();

    bool has(List<String> needles) => needles.any(s.contains);

    final kind = switch (s) {
      _ when has(['cancel', 'aborted by user']) => YoutubeErrorKind.cancelled,
      _ when has(['private video', 'is private']) =>
        YoutubeErrorKind.privateVideo,
      _ when has([
            'age-restricted',
            'age restricted',
            'inappropriate for some users',
            'confirm your age',
          ]) =>
        YoutubeErrorKind.ageRestricted,
      _ when has([
            "confirm you're not a bot",
            'sign in to confirm',
            'login required',
            'account cookies',
            'requires authentication',
          ]) =>
        YoutubeErrorKind.signInRequired,
      _ when has([
            'not available in your country',
            'blocked it in your country',
            'geo restricted',
            'geo-restricted',
          ]) =>
        YoutubeErrorKind.geoBlocked,
      _ when has([
            'live event will begin',
            'is live',
            'premieres in',
            'live stream',
          ]) =>
        YoutubeErrorKind.liveNotSupported,
      _ when has([
            'video unavailable',
            'has been removed',
            'no longer available',
            'does not exist',
            'incomplete youtube id',
          ]) =>
        YoutubeErrorKind.videoUnavailable,
      _ when has([
            'unable to extract',
            'failed to extract',
            'nsig extraction',
            'signature extraction',
            'player response',
            'update yt-dlp',
          ]) =>
        YoutubeErrorKind.extractorOutdated,
      _ when has([
            'no space left',
            'enospc',
            'insufficient storage',
            'not enough space',
          ]) =>
        YoutubeErrorKind.insufficientStorage,
      _ when has([
            'permission denied',
            'read-only file system',
            'eacces',
            'directory not found',
          ]) =>
        YoutubeErrorKind.storageUnavailable,
      _ when has([
            'failed to resolve host',
            'network is unreachable',
            'no address associated',
            'socketexception',
            'connection refused',
            'connection reset',
            'timed out',
          ]) =>
        YoutubeErrorKind.networkUnavailable,
      _ when has([
            'http error 5',
            'too many requests',
            'http error 429',
            'temporarily unavailable',
          ]) =>
        YoutubeErrorKind.temporaryYoutubeError,
      _ when has([
            'requested format is not available',
            'no video formats',
            'unsupported url',
          ]) =>
        YoutubeErrorKind.unsupportedStream,
      _ => YoutubeErrorKind.extractionFailed,
    };

    return YoutubeFailure(kind, diagnostic: raw, cause: error);
  }
}

/// Display strings. Kept apart from the enum so this file stays free of
/// Flutter imports and can be unit-tested without a widget binding; when the
/// app gains localisation these become lookup keys.
extension YoutubeErrorMessages on YoutubeErrorKind {
  String get title => switch (this) {
        YoutubeErrorKind.invalidUrl => "That's not a YouTube link",
        YoutubeErrorKind.videoUnavailable => 'Video unavailable',
        YoutubeErrorKind.privateVideo => 'This video is private',
        YoutubeErrorKind.ageRestricted => 'Age-restricted video',
        YoutubeErrorKind.signInRequired => 'YouTube wants a sign-in',
        YoutubeErrorKind.geoBlocked => 'Not available in your region',
        YoutubeErrorKind.liveNotSupported => 'Live streams not supported',
        YoutubeErrorKind.unsupportedStream => 'No usable format',
        YoutubeErrorKind.extractorOutdated => 'YouTube changed something',
        YoutubeErrorKind.temporaryYoutubeError => 'YouTube is having trouble',
        YoutubeErrorKind.extractionFailed => "Couldn't read this video",
        YoutubeErrorKind.networkUnavailable => 'No connection',
        YoutubeErrorKind.downloadFailed => 'Download failed',
        YoutubeErrorKind.storageUnavailable => 'Storage unavailable',
        YoutubeErrorKind.insufficientStorage => 'Not enough space',
        YoutubeErrorKind.cancelled => 'Cancelled',
      };

  String get detail => switch (this) {
        YoutubeErrorKind.invalidUrl =>
          'Check the link and try again. Video, Shorts and youtu.be links all work.',
        YoutubeErrorKind.videoUnavailable =>
          'It may have been deleted or made unavailable by the uploader.',
        YoutubeErrorKind.privateVideo =>
          'Only people the uploader invited can watch it.',
        YoutubeErrorKind.ageRestricted =>
          'YouTube requires a signed-in adult account for this one.',
        YoutubeErrorKind.signInRequired =>
          'YouTube is asking this device to prove it is a real viewer. Trying again in a few minutes usually clears it.',
        YoutubeErrorKind.geoBlocked =>
          'The uploader has restricted where this video can be watched.',
        YoutubeErrorKind.liveNotSupported =>
          'Try again once the stream has finished and the recording is posted.',
        YoutubeErrorKind.unsupportedStream =>
          'None of the available formats can be played or saved on this device.',
        YoutubeErrorKind.extractorOutdated =>
          'The downloader needs an update to keep working. This is not something retrying will fix.',
        YoutubeErrorKind.temporaryYoutubeError =>
          'This is usually brief. Try again shortly.',
        YoutubeErrorKind.extractionFailed =>
          'Something went wrong reading this video.',
        YoutubeErrorKind.networkUnavailable =>
          'Check your Wi-Fi or mobile data and try again.',
        YoutubeErrorKind.downloadFailed =>
          'The transfer stopped before it finished.',
        YoutubeErrorKind.storageUnavailable =>
          'The download folder is missing or cannot be written to.',
        YoutubeErrorKind.insufficientStorage =>
          'Free up some space, or pick a smaller quality.',
        YoutubeErrorKind.cancelled => '',
      };
}
