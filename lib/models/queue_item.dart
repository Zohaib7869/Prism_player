import '../models/audio_model.dart';
import '../models/video_model.dart';

enum PlaybackMode { none, video, audio }
enum RepeatMode { off, all, one }

/// Engine-agnostic representation of "one thing that can be played", built
/// from either a VideoModel or an AudioModel so the GlobalPlayerController
/// and the queue/playlist system never need to know which one they're holding.
class QueueItem {
  final String mediaRef; // "video:<id>" or "audio:<id>"
  final String path;
  final String title;
  final String? artist;
  final String? artUri; // thumbnail (video) or album art content uri (audio)
  final int durationMs;
  final bool isVideo;

  /// Set only for adaptive-quality YouTube playback (720p+): the separate
  /// audio-only stream URL that must be merged with [path] (the video-only
  /// stream) at playback time. Null for muxed streams (360p fallback) and
  /// for every non-YouTube item, where [path] alone is already playable.
  final String? audioUrl;

  const QueueItem({
    required this.mediaRef,
    required this.path,
    required this.title,
    this.artist,
    this.artUri,
    required this.durationMs,
    required this.isVideo,
    this.audioUrl,
  });

  factory QueueItem.fromVideo(VideoModel v) => QueueItem(
        mediaRef: v.mediaRef,
        path: v.path,
        title: v.title,
        artUri: v.thumbnailPath,
        durationMs: v.durationMs,
        isVideo: true,
      );

  factory QueueItem.fromAudio(AudioModel a) => QueueItem(
        mediaRef: a.mediaRef,
        path: a.path,
        title: a.title,
        artist: a.artist,
        artUri: a.albumArtUri,
        durationMs: a.durationMs,
        isVideo: false,
      );

  String get mediaId => mediaRef.split(':').last;

  /// True when [path] is a network stream (YouTube) rather than a file on
  /// disk. Library bookkeeping (resume position, play counts, subtitles
  /// sidecar lookup) is naturally skipped for these because no Hive record
  /// exists for the id.
  bool get isRemote => path.startsWith('http://') || path.startsWith('https://');

  /// True for items that came from a YouTube search result — these are the
  /// only remote items with a resolvable quality/captions menu, since
  /// [mediaId] is a real YouTube video id only for them.
  bool get isYoutube => mediaRef.startsWith('youtube:');

  factory QueueItem.fromYoutube({
    required String videoId,
    required String streamUrl,
    required String title,
    String? author,
    String? thumbnailUrl,
    required int durationMs,
    String? audioUrl,
  }) =>
      QueueItem(
        mediaRef: 'youtube:$videoId',
        path: streamUrl,
        title: title,
        artist: author,
        artUri: thumbnailUrl,
        durationMs: durationMs,
        isVideo: true,
        audioUrl: audioUrl,
      );
}
