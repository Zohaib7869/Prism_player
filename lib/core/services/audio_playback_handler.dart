import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../models/queue_item.dart';

/// The single engine that actually plays audio (Music library, and any video
/// played in "Play as Audio" mode). Wrapping it in a BaseAudioHandler gives us,
/// for free: the Android media-session notification with play/pause/next/prev
/// artwork, lock-screen controls, and continued playback when the app is
/// backgrounded or the screen is off — all via the standard audio_service
/// foreground service declared in AndroidManifest.xml.
///
/// GlobalPlayerController is the only class that talks to this handler; UI
/// code never touches it directly.
class AudioPlaybackHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer player = AudioPlayer();

  List<QueueItem> _queueItems = [];
  int _currentIndex = 0;
  Timer? _notificationTicker;

  AudioPlaybackHandler() {
    _listenForDurationChanges();
    _listenForCurrentSongIndexChanges();
    _broadcastPlaybackState();
    // The system notification's play/pause icon and its progress/duration
    // seekbar are both driven off `playbackState`, which — same root cause
    // as the in-app scrubber (see GlobalPlayerController._positionTicker) —
    // only gets a new value from `playbackEventStream` on real events
    // (buffering, track-ready, track-change...), not on a regular clock.
    // A track that's just quietly playing never fires one, so the
    // notification was left showing a stale snapshot: whatever position it
    // had at the last buffering/ready event, and a play/pause icon that
    // only ever updated by coincidence whenever some other event happened
    // to fire around the same time as a tap. Re-publishing playbackState on
    // a short timer keeps the notification's icon and seekbar live and in
    // sync with the actual player, exactly like the in-app UI.
    _notificationTicker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_latestEvent != null) {
        playbackState.add(_transformEvent(_latestEvent!, player.playing));
      }
    });
  }

  int? get androidAudioSessionId => player.androidAudioSessionId;

  Future<void> loadQueue(List<QueueItem> items, {int startIndex = 0}) async {
    _queueItems = items;
    _currentIndex = startIndex;
    queue.add(items
        .map((i) => MediaItem(
              id: i.mediaRef,
              title: i.title,
              artist: i.artist,
              artUri: i.artUri != null ? Uri.tryParse(i.artUri!) : null,
              duration: Duration(milliseconds: i.durationMs),
              extras: {'path': i.path},
            ))
        .toList());
    await player.setAudioSource(
      ConcatenatingAudioSource(
        children: items.map((i) => AudioSource.uri(Uri.file(i.path))).toList(),
      ),
      initialIndex: startIndex,
    );
    mediaItem.add(queue.value.isNotEmpty ? queue.value[startIndex] : null);
  }

  /// Loads a single file directly (used by "Play as Audio" for a video, and
  /// by any ad-hoc single-item playback) without building a ConcatenatingAudioSource.
  Future<void> loadSingle(QueueItem item, {Duration? initialPosition}) async {
    _queueItems = [item];
    _currentIndex = 0;
    final mi = MediaItem(
      id: item.mediaRef,
      title: item.title,
      artist: item.artist,
      artUri: item.artUri != null ? Uri.tryParse(item.artUri!) : null,
      duration: Duration(milliseconds: item.durationMs),
      extras: {'path': item.path},
    );
    queue.add([mi]);
    mediaItem.add(mi);
    await player.setAudioSource(AudioSource.uri(Uri.file(item.path)));
    if (initialPosition != null) await player.seek(initialPosition);
  }

  QueueItem? get currentItem => _queueItems.isEmpty ? null : _queueItems[_currentIndex];

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    // Note: the notification ticker is intentionally left running across
    // stop() — this handler is a single long-lived instance for the app's
    // whole process lifetime (see main.dart), and playback can be started
    // again later via loadQueue/loadSingle on the same instance, at which
    // point the ticker needs to already be ticking for the next session's
    // notification to stay live.
    await player.stop();
    return super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (player.hasNext) {
      await player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.hasPrevious) {
      await player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queueItems.length) return;
    await player.seek(Duration.zero, index: index);
  }

  Future<void> setSpeedValue(double speed) => player.setSpeed(speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        await player.setLoopMode(LoopMode.all);
        break;
    }
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  void _listenForDurationChanges() {
    player.durationStream.listen((duration) {
      final index = player.currentIndex;
      if (index == null || duration == null) return;
      final newQueue = List<MediaItem>.from(queue.value);
      if (index < 0 || index >= newQueue.length) return;
      newQueue[index] = newQueue[index].copyWith(duration: duration);
      queue.add(newQueue);
    });
  }

  void _listenForCurrentSongIndexChanges() {
    player.currentIndexStream.listen((index) {
      if (index == null) return;
      _currentIndex = index;
      final q = queue.value;
      if (index >= 0 && index < q.length) mediaItem.add(q[index]);
    });
  }

  PlaybackEvent? _latestEvent;

  void _broadcastPlaybackState() {
    Rx.combineLatest2<PlaybackEvent, bool, PlaybackState>(
      player.playbackEventStream,
      player.playingStream,
      (event, playing) {
        _latestEvent = event;
        return _transformEvent(event, playing);
      },
    ).listen(playbackState.add);
  }

  PlaybackState _transformEvent(PlaybackEvent event, bool playing) {
    return PlaybackState(
      // Stop was dropped from here — the notification only has room for 3
      // well-centered controls (previous / play-pause / next), and a
      // separate stop button was both redundant with swiping the
      // notification away and, together with 4 controls, unbalanced the
      // compact notification layout.
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      // Indices into `controls` above to show in the compact/collapsed
      // notification. With stop removed, all 3 remaining controls
      // (previous, play/pause, next) fit and render evenly centered.
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (event.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
    );
  }
}
