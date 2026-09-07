import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart' as svc;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_player/video_player.dart';

import '../../models/audio_model.dart';
import '../../models/queue_item.dart';
import '../../models/video_model.dart';
import '../../repositories/media_repository.dart';
import '../../repositories/eq_settings_repository.dart';
import '../../repositories/settings_repository.dart';
import 'album_art_service.dart';
import 'audio_playback_handler.dart';
import 'audio_visualizer_service.dart';
import 'equalizer_service.dart';
import 'youtube_service.dart';
import 'yt_log.dart';

class PlayerUiState {
  final PlaybackMode mode;
  final List<QueueItem> queue;
  final int currentIndex;
  final bool isPlaying;
  final bool isBuffering;
  final Duration position;
  final Duration duration;
  final double speed;
  final RepeatMode repeat;
  final bool shuffle;
  final int volumeBoostPercent;
  final VideoPlayerController? videoController;
  final mk.Player? mkPlayer;
  final mkv.VideoController? mkVideoController;
  final String? errorMessage;

  const PlayerUiState({
    this.mode = PlaybackMode.none,
    this.queue = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.isBuffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.repeat = RepeatMode.off,
    this.shuffle = false,
    this.volumeBoostPercent = 100,
    this.videoController,
    this.mkPlayer,
    this.mkVideoController,
    this.errorMessage,
  });

  QueueItem? get current => (queue.isEmpty || currentIndex >= queue.length) ? null : queue[currentIndex];
  bool get hasMedia => current != null;
  bool get hasNext => currentIndex < queue.length - 1 || repeat == RepeatMode.all;
  bool get hasPrevious => currentIndex > 0;

  PlayerUiState copyWith({
    PlaybackMode? mode,
    List<QueueItem>? queue,
    int? currentIndex,
    bool? isPlaying,
    bool? isBuffering,
    Duration? position,
    Duration? duration,
    double? speed,
    RepeatMode? repeat,
    bool? shuffle,
    int? volumeBoostPercent,
    VideoPlayerController? videoController,
    bool clearVideoController = false,
    mk.Player? mkPlayer,
    mkv.VideoController? mkVideoController,
    bool clearMkController = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlayerUiState(
      mode: mode ?? this.mode,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
      repeat: repeat ?? this.repeat,
      shuffle: shuffle ?? this.shuffle,
      volumeBoostPercent: volumeBoostPercent ?? this.volumeBoostPercent,
      videoController: clearVideoController ? null : (videoController ?? this.videoController),
      mkPlayer: clearMkController ? null : (mkPlayer ?? this.mkPlayer),
      mkVideoController: clearMkController ? null : (mkVideoController ?? this.mkVideoController),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class GlobalPlayerController extends StateNotifier<PlayerUiState> {
  final AudioPlaybackHandler audioHandler;
  final EqualizerService equalizerService;
  final MediaRepository mediaRepository;
  final SettingsRepository settingsRepository;
  final EqSettingsRepository eqSettingsRepository;
  final AlbumArtService albumArtService;
  final YoutubeService youtubeService;

  StreamSubscription? _audioPlaybackSub;
  StreamSubscription? _audioMediaItemSub;
  Timer? _progressSaveTimer;
  Timer? _positionTicker;
  List<int> _shuffleOrder = [];
  final List<StreamSubscription> _mkSubs = [];
  
  void _clearMkSubs() {
    for (final sub in _mkSubs) {
      sub.cancel();
    }
    _mkSubs.clear();
  }

  bool _audioEngineHoldsSingleItem = false;

  GlobalPlayerController({
    required this.audioHandler,
    required this.equalizerService,
    required this.mediaRepository,
    required this.settingsRepository,
    required this.eqSettingsRepository,
    required this.albumArtService,
    required this.youtubeService,
  }) : super(PlayerUiState(volumeBoostPercent: eqSettingsRepository.current.volumeBoostPercent)) {
    _listenToAudioHandler();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
    _positionTicker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tickPosition());
  }

  void _tickPosition() {
    try {
      if (state.mode == PlaybackMode.audio && state.isPlaying) {
        state = state.copyWith(position: audioHandler.player.position);
      } else if (state.mode == PlaybackMode.video) {
        final controller = state.videoController;
        final player = state.mkPlayer;
        if (controller != null && controller.value.isPlaying) {
          state = state.copyWith(position: controller.value.position);
        } else if (player != null && player.state.playing) {
          state = state.copyWith(position: player.state.position);
        }
      }
    } catch (_) {}
  }

  void _prefetchArt(QueueItem item) {
    final uri = item.artUri;
    if (uri != null && uri.startsWith('content://')) {
      unawaited(albumArtService.load(uri));
    }
  }

  List<QueueItem> _neighborsOf(List<QueueItem> items, int index) {
    final neighbors = <QueueItem>[];
    if (index + 1 < items.length) neighbors.add(items[index + 1]);
    if (index - 1 >= 0) neighbors.add(items[index - 1]);
    return neighbors;
  }

  Future<void> playVideo(VideoModel video, {List<VideoModel>? queueVideos, int? startIndex}) async {
    // Any YouTube resolve still in flight is no longer what the user wants.
    ++_resolveToken;
    final videos = queueVideos ?? [video];
    final items = videos.map(QueueItem.fromVideo).toList();
    final index = startIndex ?? videos.indexWhere((v) => v.id == video.id).clamp(0, items.length - 1);

    await _stopAudioEngine();
    _audioEngineHoldsSingleItem = false;

    state = state.copyWith(
      mode: PlaybackMode.video,
      queue: items,
      currentIndex: index,
      clearError: true,
    );

    await _startVideoAtIndex(index);
  }

  Future<void> playRemoteVideo(QueueItem item) async {
    // Any YouTube resolve still in flight is no longer what the user wants.
    ++_resolveToken;
    await _stopAudioEngine();
    _audioEngineHoldsSingleItem = false;

    final oldController = state.videoController;
    final oldMkPlayer = state.mkPlayer;

    state = state.copyWith(
      mode: PlaybackMode.video,
      queue: [item],
      currentIndex: 0,
      clearError: true,
      clearVideoController: true,
      clearMkController: true,
    );

    unawaited(oldController?.dispose());
    unawaited(oldMkPlayer?.dispose());
    unawaited(_startVideoAtIndex(0));
  }

  /// Entry point for "user tapped a YouTube search result".
  ///
  /// Puts the player into video mode straight away using only the search
  /// metadata (title, thumbnail, duration) and *then* resolves the stream in
  /// the background. The video player screen already renders a loading state
  /// while both controllers are null, so the caller can push the route
  /// immediately instead of holding the user on the results list behind a
  /// blocking spinner for the whole resolve.
  Future<void> openYoutube({
    required String videoId,
    required String title,
    String? author,
    String? thumbnailUrl,
    required int durationMs,
  }) async {
    final token = ++_resolveToken;
    // Invalidate any _startVideoAtIndex still in flight from a previous tap.
    ++_playToken;
    _remoteWatchdog?.cancel();

    QueueItem itemWith({String url = '', String? audio}) => QueueItem.fromYoutube(
          videoId: videoId,
          streamUrl: url,
          audioUrl: audio,
          title: title,
          author: author,
          thumbnailUrl: thumbnailUrl,
          durationMs: durationMs,
        );

    await _stopAudioEngine();
    _audioEngineHoldsSingleItem = false;

    final oldController = state.videoController;
    final oldMkPlayer = state.mkPlayer;
    _clearMkSubs();

    // Placeholder item — no stream URL yet, but enough for the player screen
    // to show the video's title and thumbnail behind the spinner rather than
    // a black void.
    state = state.copyWith(
      mode: PlaybackMode.video,
      queue: [itemWith()],
      currentIndex: 0,
      position: Duration.zero,
      duration: Duration.zero,
      clearError: true,
      clearVideoController: true,
      clearMkController: true,
      isPlaying: false,
      isBuffering: true,
    );

    unawaited(oldController?.dispose());
    unawaited(oldMkPlayer?.dispose());

    try {
      final stream = await youtubeService.resolveStreamUrl(videoId);
      // The user tapped a different video (or backed out) while we were
      // waiting — drop this result on the floor.
      if (token != _resolveToken) return;
      state = state.copyWith(
        queue: [itemWith(url: stream.videoUrl, audio: stream.audioUrl)],
        currentIndex: 0,
      );
      await _startVideoAtIndex(0);
    } catch (e) {
      if (token != _resolveToken) return;
      debugPrint('[youtube] resolve failed for $videoId — $e');
      state = state.copyWith(
        errorMessage: 'Could not start this video.\n'
            'YouTube may be blocking it — try another one.',
        isBuffering: false,
        isPlaying: false,
      );
    }
  }

  Future<void> switchRemoteQuality(String url, {String? audioUrl}) async {
    final item = state.current;
    if (item == null || !item.isRemote) return;
    final resumeAt = state.mkPlayer?.state.position ?? state.videoController?.value.position ?? state.position;
    final newItem = QueueItem.fromYoutube(
      videoId: item.mediaId,
      streamUrl: url,
      audioUrl: audioUrl,
      title: item.title,
      author: item.artist,
      thumbnailUrl: item.artUri,
      durationMs: item.durationMs,
    );
    state = state.copyWith(queue: [newItem], currentIndex: 0, clearError: true);
    await _startVideoAtIndex(0, seekTo: resumeAt);
  }

  Future<void> playAudio(AudioModel audio, {List<AudioModel>? queueAudio, int? startIndex}) async {
    // Any YouTube resolve still in flight is no longer what the user wants.
    ++_resolveToken;
    final audios = queueAudio ?? [audio];
    final items = audios.map(QueueItem.fromAudio).toList();
    final index = startIndex ?? audios.indexWhere((a) => a.id == audio.id).clamp(0, items.length - 1);

    _prefetchArt(items[index]);
    for (final neighbor in _neighborsOf(items, index)) {
      _prefetchArt(neighbor);
    }

    await state.videoController?.dispose();
    _clearMkSubs();
    await state.mkPlayer?.dispose();
    _audioEngineHoldsSingleItem = false;
    state = state.copyWith(
      mode: PlaybackMode.audio,
      queue: items,
      currentIndex: index,
      clearVideoController: true,
      clearMkController: true,
      clearError: true,
      speed: settingsRepository.defaultPlaybackSpeed,
    );

    await audioHandler.loadQueue(items, startIndex: index);
    await audioHandler.setSpeedValue(state.speed);
    if (settingsRepository.resumePlayback) {
      final lastMs = mediaRepository.audioById(items[index].mediaId)?.lastPositionMs ?? 0;
      if (lastMs > 0) await audioHandler.seek(Duration(milliseconds: lastMs));
    }
    await _attachEqualizerToAudioSession();
    await audioHandler.play();
    await mediaRepository.recordAudioPlayed(items[index].mediaId);
  }

  Future<void> playLocalFile(QueueItem item) async {
    // Any YouTube resolve still in flight is no longer what the user wants.
    ++_resolveToken;
    await _stopAudioEngine();
    _audioEngineHoldsSingleItem = false;

    if (item.isVideo) {
      state = state.copyWith(
        mode: PlaybackMode.video,
        queue: [item],
        currentIndex: 0,
        clearError: true,
        speed: settingsRepository.defaultPlaybackSpeed,
      );
      await _startVideoAtIndex(0);
      return;
    }

    await state.videoController?.dispose();
    _clearMkSubs();
    await state.mkPlayer?.dispose();
    state = state.copyWith(
      mode: PlaybackMode.audio,
      queue: [item],
      currentIndex: 0,
      clearVideoController: true,
      clearMkController: true,
      clearError: true,
      speed: settingsRepository.defaultPlaybackSpeed,
    );

    _audioEngineHoldsSingleItem = true;
    await audioHandler.loadSingle(item);
    await _attachEqualizerToAudioSession();
    await equalizerService.setVolumeBoostPercent(state.volumeBoostPercent);
    await audioHandler.play();
  }

  Future<void> playAsAudio() async {
    if (state.mode != PlaybackMode.video || state.current == null) return;
    final item = state.current!;
    final position = state.position;

    await state.videoController?.pause();
    await state.videoController?.dispose();
    await state.mkPlayer?.pause();
    _clearMkSubs();
    await state.mkPlayer?.dispose();
    state = state.copyWith(mode: PlaybackMode.audio, clearVideoController: true, clearMkController: true);

    _audioEngineHoldsSingleItem = true;
    await audioHandler.loadSingle(item, initialPosition: position);
    await _attachEqualizerToAudioSession();
    await equalizerService.setVolumeBoostPercent(state.volumeBoostPercent);
    await audioHandler.play();
  }

  Future<void> playAsVideo() async {
    if (state.mode != PlaybackMode.audio || state.current == null || !state.current!.isVideo) return;
    final position = audioHandler.player.position;
    await audioHandler.pause();
    _audioEngineHoldsSingleItem = false;

    state = state.copyWith(mode: PlaybackMode.video, clearVideoController: true, clearMkController: true);
    await _startVideoAtIndex(state.currentIndex, seekTo: position);
  }

  Future<void> togglePlayPause() async {
    if (state.mode == PlaybackMode.video) {
      final controller = state.videoController;
      final player = state.mkPlayer;
      if (controller != null) {
        if (controller.value.isPlaying) {
          await controller.pause();
        } else {
          await controller.play();
        }
      } else if (player != null) {
        if (player.state.playing) {
          await player.pause();
        } else {
          await player.play();
        }
      }
    } else if (state.mode == PlaybackMode.audio) {
      if (state.isPlaying) {
        await audioHandler.pause();
      } else {
        await audioHandler.play();
      }
    }
  }

  Future<void> seekTo(Duration position) async {
    if (state.mode == PlaybackMode.video) {
      if (state.videoController != null) {
        await state.videoController?.seekTo(position);
      } else {
        await state.mkPlayer?.seek(position);
      }
    } else if (state.mode == PlaybackMode.audio) {
      await audioHandler.seek(position);
    }
    state = state.copyWith(position: position);
  }

  Future<void> seekRelative(Duration delta) async {
    // Read the live position straight off the engine. state.position is
    // refreshed by a 250ms ticker that only runs while isPlaying is true, so
    // after a pause — or in the gap right after a previous seek — it can be
    // up to a quarter second stale, which made repeated double-taps drift.
    final current = _enginePosition() ?? state.position;
    final duration = _engineDuration() ?? state.duration;

    var target = current + delta;
    if (target < Duration.zero) target = Duration.zero;

    // ROOT CAUSE of "double-tap right jumps to 0:00": the old code clamped
    // with `target > state.duration ? state.duration : target`. When duration
    // is Duration.zero — which it is until the engine reports it, and for the
    // whole of a remote resolve — every positive target is greater than zero,
    // so the clamp returned Duration.zero and every forward seek went to the
    // start. Backward seeks also landed on zero, which looked correct and hid
    // the bug. Only clamp when the duration is actually known.
    if (duration > Duration.zero && target > duration) {
      target = duration - const Duration(milliseconds: 500);
      if (target < Duration.zero) target = Duration.zero;
    }

    await seekTo(target);
  }

  /// Live position from whichever engine is active, or null when none is.
  Duration? _enginePosition() {
    if (state.mode == PlaybackMode.video) {
      final vc = state.videoController;
      if (vc != null && vc.value.isInitialized) return vc.value.position;
      final mk = state.mkPlayer;
      if (mk != null) return mk.state.position;
    } else if (state.mode == PlaybackMode.audio) {
      return audioHandler.player.position;
    }
    return null;
  }

  /// Live duration from whichever engine is active. Returns null rather than
  /// zero when unknown, so callers can tell "not known yet" from "zero long".
  Duration? _engineDuration() {
    if (state.mode == PlaybackMode.video) {
      final vc = state.videoController;
      if (vc != null && vc.value.isInitialized && vc.value.duration > Duration.zero) {
        return vc.value.duration;
      }
      final mk = state.mkPlayer;
      if (mk != null && mk.state.duration > Duration.zero) return mk.state.duration;
    } else if (state.mode == PlaybackMode.audio) {
      return audioHandler.player.duration;
    }
    return null;
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    if (state.mode == PlaybackMode.video) {
      if (state.videoController != null) {
        await state.videoController?.setPlaybackSpeed(speed);
      } else {
        await state.mkPlayer?.setRate(speed == 0 ? 1.0 : speed);
      }
    } else if (state.mode == PlaybackMode.audio) {
      await audioHandler.setSpeedValue(speed);
    }
  }

  Future<void> setRepeatMode(RepeatMode mode) async {
    state = state.copyWith(repeat: mode);
    final mapped = switch (mode) {
      RepeatMode.off => svc.AudioServiceRepeatMode.none,
      RepeatMode.one => svc.AudioServiceRepeatMode.one,
      RepeatMode.all => svc.AudioServiceRepeatMode.all,
    };
    await audioHandler.setRepeatMode(mapped);
  }

  Future<void> toggleShuffle() async {
    final newValue = !state.shuffle;
    state = state.copyWith(shuffle: newValue);
    _shuffleOrder = newValue ? _buildShuffleOrder() : [];
    await audioHandler.setShuffleMode(
      newValue ? svc.AudioServiceShuffleMode.all : svc.AudioServiceShuffleMode.none,
    );
  }

  List<int> _buildShuffleOrder() {
    final indices = List<int>.generate(state.queue.length, (i) => i)..remove(state.currentIndex);
    indices.shuffle(Random());
    return [state.currentIndex, ...indices];
  }

  Future<void> skipNext() async {
    if (state.queue.length <= 1) return;
    final nextIndex = _resolveNextIndex();
    if (nextIndex == null) return;
    await _goToIndex(nextIndex);
  }

  Future<void> skipPrevious() async {
    if (state.queue.length <= 1) return;
    if (state.position > const Duration(seconds: 3)) {
      await seekTo(Duration.zero);
      return;
    }
    final prevIndex = _resolvePreviousIndex();
    if (prevIndex == null) return;
    await _goToIndex(prevIndex);
  }

  int? _resolveNextIndex() {
    if (state.shuffle && _shuffleOrder.isNotEmpty) {
      final pos = _shuffleOrder.indexOf(state.currentIndex);
      if (pos + 1 < _shuffleOrder.length) return _shuffleOrder[pos + 1];
      return state.repeat == RepeatMode.all ? _shuffleOrder.first : null;
    }
    if (state.currentIndex + 1 < state.queue.length) return state.currentIndex + 1;
    return state.repeat == RepeatMode.all ? 0 : null;
  }

  int? _resolvePreviousIndex() {
    if (state.shuffle && _shuffleOrder.isNotEmpty) {
      final pos = _shuffleOrder.indexOf(state.currentIndex);
      if (pos > 0) return _shuffleOrder[pos - 1];
      return null;
    }
    if (state.currentIndex > 0) return state.currentIndex - 1;
    return null;
  }

  Future<void> playQueueIndex(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    if (index == state.currentIndex) return;
    await _goToIndex(index);
  }

  Future<void> _goToIndex(int index) async {
    await _saveProgress();
    if (state.mode == PlaybackMode.audio) {
      if (_audioEngineHoldsSingleItem) {
        _audioEngineHoldsSingleItem = false;
        await audioHandler.loadQueue(state.queue, startIndex: index);
        await audioHandler.setSpeedValue(state.speed);
        await _attachEqualizerToAudioSession();
        await audioHandler.play();
      } else {
        await audioHandler.skipToQueueItem(index);
      }
      state = state.copyWith(currentIndex: index);
    } else {
      state = state.copyWith(currentIndex: index);
      await _startVideoAtIndex(index);
    }
    final item = state.queue[index];
    if (item.isVideo) {
      await mediaRepository.recordVideoPlayed(item.mediaId);
    } else {
      await mediaRepository.recordAudioPlayed(item.mediaId);
    }
  }

  Future<void> setVolumeBoostPercent(int percent) async {
    state = state.copyWith(volumeBoostPercent: percent);
    final saved = eqSettingsRepository.current..volumeBoostPercent = percent;
    await eqSettingsRepository.save(saved);
    if (state.mode == PlaybackMode.audio) {
      await equalizerService.setVolumeBoostPercent(percent);
    }
  }

  bool get isEqualizerLive => state.mode == PlaybackMode.audio && equalizerService.isAttached;

  Future<void> setEqualizerEnabled(bool enabled) async {
    final saved = eqSettingsRepository.current..equalizerEnabled = enabled;
    await eqSettingsRepository.save(saved);
    if (isEqualizerLive) await _safeEq(() => equalizerService.setEqualizerEnabled(enabled));
  }

  Future<void> setEqualizerPreset(int index, List<int> curveMb) async {
    final saved = eqSettingsRepository.current
      ..presetIndex = index
      ..bandLevelsMb = curveMb;
    await eqSettingsRepository.save(saved);
    if (isEqualizerLive) {
      for (var band = 0; band < curveMb.length; band++) {
        final level = curveMb[band];
        await _safeEq(() => equalizerService.setBandLevel(band, level));
      }
    }
  }

  Future<void> setEqualizerBand(int band, int levelMb) async {
    final saved = eqSettingsRepository.current;
    final levels = [...saved.bandLevelsMb];
    while (levels.length <= band) {
      levels.add(0);
    }
    levels[band] = levelMb;
    saved
      ..bandLevelsMb = levels
      ..presetIndex = -1;
    await eqSettingsRepository.save(saved);
    if (isEqualizerLive) await _safeEq(() => equalizerService.setBandLevel(band, levelMb));
  }

  int _effectiveStrength(bool enabled, int strength) => (enabled && strength <= 0) ? 700 : strength;

  Future<void> setBassBoost(bool enabled, int strength) async {
    final effective = _effectiveStrength(enabled, strength);
    final saved = eqSettingsRepository.current
      ..bassBoostEnabled = enabled
      ..bassBoostStrength = effective;
    await eqSettingsRepository.save(saved);
    if (isEqualizerLive) {
      await _safeEq(() => equalizerService.setBassBoostEnabled(enabled));
      await _safeEq(() => equalizerService.setBassBoostStrength(effective));
    }
  }

  Future<void> setVirtualizer(bool enabled, int strength) async {
    final effective = _effectiveStrength(enabled, strength);
    final saved = eqSettingsRepository.current
      ..virtualizerEnabled = enabled
      ..virtualizerStrength = effective;
    await eqSettingsRepository.save(saved);
    if (isEqualizerLive) {
      await _safeEq(() => equalizerService.setVirtualizerEnabled(enabled));
      await _safeEq(() => equalizerService.setVirtualizerStrength(effective));
    }
  }

  Future<void> _attachEqualizerToAudioSession() async {
    int? sessionId;
    for (var attempt = 0; attempt < 10; attempt++) {
      await Future.delayed(const Duration(milliseconds: 150));
      sessionId = audioHandler.androidAudioSessionId;
      if (sessionId != null && sessionId != 0) break;
    }
    if (sessionId == null || sessionId == 0) return;
    await _safeEq(() => equalizerService.attach(sessionId!));
    await _safeEq(() => AudioVisualizerService.instance.attach(sessionId!));

    final saved = eqSettingsRepository.current;
    await _safeEq(() => equalizerService.setEqualizerEnabled(saved.equalizerEnabled));
    for (var band = 0; band < saved.bandLevelsMb.length; band++) {
      final level = saved.bandLevelsMb[band];
      await _safeEq(() => equalizerService.setBandLevel(band, level));
    }
    await _safeEq(() => equalizerService.setBassBoostEnabled(saved.bassBoostEnabled));
    await _safeEq(() => equalizerService.setBassBoostStrength(
        _effectiveStrength(saved.bassBoostEnabled, saved.bassBoostStrength)));
    await _safeEq(() => equalizerService.setVirtualizerEnabled(saved.virtualizerEnabled));
    await _safeEq(() => equalizerService.setVirtualizerStrength(
        _effectiveStrength(saved.virtualizerEnabled, saved.virtualizerStrength)));
    await _safeEq(() => equalizerService.setVolumeBoostPercent(state.volumeBoostPercent));
  }

  Future<void> _safeEq(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      debugPrint('EqualizerService call failed (non-fatal): $e');
    }
  }

  int _playToken = 0;
  /// Separate from [_playToken] so a background YouTube resolve can tell
  /// whether it is still the one the user is waiting for, without being
  /// invalidated by the _startVideoAtIndex it goes on to trigger itself.
  int _resolveToken = 0;
  /// Bumped whenever a different item starts, so a seek still polling for the
  /// previous media gives up instead of yanking the new one to a stale offset.
  int _seekGeneration = 0;
  Timer? _remoteWatchdog;
  Timer? _ladderWarmup;

  Future<void> _startVideoAtIndex(int index, {Duration? seekTo}) async {
    final token = ++_playToken;
    _seekGeneration++;
    _ladderWarmup?.cancel();
    _remoteWatchdog?.cancel();

    await state.videoController?.dispose();
    _clearMkSubs();
    await state.mkPlayer?.dispose();

    final item = state.queue[index];
    final resumeMs = seekTo?.inMilliseconds ??
        (settingsRepository.resumePlayback
            ? (mediaRepository.videoById(item.mediaId)?.lastPositionMs ?? 0)
            : 0);

    if (item.isRemote) {
      await _startRemoteVideo(item, index, token, resumeMs);
    } else {
      await _startLocalVideo(item, index, token, resumeMs);
    }
  }

  /// Sets mpv's `start` option, which is applied while the media loads rather
  /// than afterwards.
  ///
  /// A post-open `seek` is the wrong tool for these streams. The log shows it
  /// being issued, accepted, and simply not taking — three verified retries in
  /// a row left playback at zero. `start` instead makes mpv open the stream at
  /// the offset in the first place, so there is no second request for
  /// googlevideo to refuse and no window in which the position can be reset by
  /// a fallback re-open.
  Future<void> _setStartPosition(mk.Player player, int resumeMs) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;
    try {
      await platform.setProperty(
        'start',
        resumeMs > 500 ? (resumeMs / 1000).toStringAsFixed(3) : 'none',
      );
    } catch (e) {
      debugPrint('[mpv] could not set start position: $e');
    }
  }

  /// Seeks once the media is actually ready to be seeked.
  ///
  /// Issuing `seek` straight after `open` races the demuxer: mpv has accepted
  /// the URL but has not parsed enough of the container to know where to jump
  /// to, so the command comes back as "error running command _command(seek,
  /// ...)" and is silently dropped. Waiting for a non-zero duration is the
  /// cheapest reliable signal that the seek will land.
  Future<void> _seekWhenReady(mk.Player player, int resumeMs) async {
    if (resumeMs <= 500) return;
    final generation = _seekGeneration;
    final target = Duration(milliseconds: resumeMs);
    final deadline = DateTime.now().add(const Duration(seconds: 15));

    try {
      // Polled, not awaited on the stream. `player.stream.duration` is a
      // broadcast stream, so a duration that arrives in the gap between the
      // state check and the subscription is missed outright, and firstWhere
      // then sits waiting for an event that has already been and gone.
      while (player.state.duration <= Duration.zero) {
        if (DateTime.now().isAfter(deadline)) return;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (generation != _seekGeneration) return;
      }

      // Verify rather than assume. mpv accepts a seek while it is still
      // swapping media and then quietly drops it, and the muxed fallback can
      // re-open the media underneath us at any point — either way playback
      // ends up sitting at 00:00 with the seek reported as sent.
      // Backup only: mpv's `start` option should already have opened the
      // stream at the right offset, so this is here for the case where the
      // media was re-opened underneath us.
      if (player.state.position >= target - const Duration(seconds: 3)) return;
      for (var attempt = 0; attempt < 2; attempt++) {
        await player.seek(target);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (generation != _seekGeneration) return;
        if (player.state.position >= target - const Duration(seconds: 3)) return;
        if (DateTime.now().isAfter(deadline)) return;
        debugPrint('[mpv] seek to ${resumeMs}ms did not take, retrying');
      }
    } catch (e) {
      debugPrint('[mpv] could not restore position ${resumeMs}ms: $e');
    }
  }

  /// Swaps the player over to a progressive (muxed) stream after mpv has
  /// rejected the adaptive pair. The first call is served from the URL the
  /// resolve already put aside, so it costs no network round trip at all.
  Future<void> _runMuxedFallback(
    mk.Player player,
    QueueItem item,
    int token,
    Map<String, String> extraHeaders,
    int resumeMs,
  ) async {
    final url = await youtubeService.muxedFallbackUrl(item.mediaId);
    if (url == null || token != _playToken) {
      _failRemote(
        player,
        'This video could not be streamed.\n'
        'YouTube may be blocking it — try another video or quality.',
      );
      return;
    }
    try {
      await _setStartPosition(player, resumeMs);
      await player.open(mk.Media(url, httpHeaders: extraHeaders), play: true);
      debugPrint('[mpv] recovered with progressive stream');
      // Re-apply the position. Without this, switching quality always dropped
      // you back to 00:00 — the seek was issued against the adaptive media
      // that mpv had just refused, so it errored out, and this re-open then
      // started a fresh stream from the beginning with nothing to restore it.
      unawaited(_seekWhenReady(player, resumeMs));
      // Give the recovered stream its own grace period.
      _remoteWatchdog?.cancel();
      _remoteWatchdog = Timer(const Duration(seconds: 25), () {
        if (state.mkPlayer != player) return;
        if (state.position > Duration.zero || state.duration > Duration.zero) return;
        _failRemote(player, 'This video would not start streaming.');
      });
    } catch (e) {
      _failRemote(player, 'Could not play this stream: $e');
    }
  }

  Future<void> _startLocalVideo(QueueItem item, int index, int token, int resumeMs) async {
    final controller = VideoPlayerController.file(File(item.path));
    try {
      await controller.initialize();
    } catch (e) {
      unawaited(controller.dispose());
      if (token != _playToken) return;
      state = state.copyWith(
        errorMessage: 'Could not play this video: unsupported format or corrupt file.',
        clearVideoController: true,
        isPlaying: false,
      );
      return;
    }

    if (token != _playToken) {
      unawaited(controller.dispose());
      return;
    }

    await controller.setPlaybackSpeed(state.speed == 0 ? 1.0 : state.speed);
    if (resumeMs > 500) {
      await controller.seekTo(Duration(milliseconds: resumeMs));
    }

    state = state.copyWith(
      videoController: controller,
      clearMkController: true,
      duration: controller.value.duration,
      position: controller.value.position,
      isPlaying: true,
    );

    controller.addListener(() => _onVideoTick(controller, item.mediaId));
    await controller.play();
    await mediaRepository.recordVideoPlayed(item.mediaId);
  }

  void _failRemote(mk.Player player, String message) {
    if (state.mkPlayer != player) return;
    _remoteWatchdog?.cancel();
    _clearMkSubs();
    unawaited(player.dispose());
    state = state.copyWith(
      errorMessage: message,
      clearMkController: true,
      isPlaying: false,
    );
  }

  Future<void> _startRemoteVideo(QueueItem item, int index, int token, int resumeMs) async {
    _remoteWatchdog?.cancel();

    final player = mk.Player(
      configuration: mk.PlayerConfiguration(
        // 32 MiB rather than 64. The demuxer cache is also what backward seeks
        // are served from, but an oversized cap just makes mpv read ahead more
        // aggressively than googlevideo wants to be read, which invites
        // throttling on progressive streams.
        bufferSize: 32 * 1024 * 1024,
        // `warn` even in release: without it, a stream failure reaches us as a
        // bare "Failed to open" with no HTTP status attached, which is not
        // enough to tell an expired URL from a blocked client.
        logLevel: kDebugMode ? mk.MPVLogLevel.info : mk.MPVLogLevel.warn,
      ),
    );

    final videoController = mkv.VideoController(player);

    // Always listen, not just in debug. You run this on a device in release
    // mode, and in release the only thing that reached the console was our own
    // "[mpv] error: Failed to open <url>" line — mpv's own message, which
    // carries the actual HTTP status, was being dropped. Without that status
    // there is no way to tell an expired URL from a blocked client.
    _mkSubs.add(player.stream.log.listen((log) {
      if (!kDebugMode &&
          log.level != 'warn' &&
          log.level != 'error' &&
          log.level != 'fatal') {
        return;
      }
      debugPrint('[mpv/${log.level}] ${log.prefix}: ${log.text}');
    }));
    final allHeaders = youtubeService.streamHeadersFor(item.mediaId);
    final userAgent = allHeaders['user-agent'] ??
        allHeaders['User-Agent'] ??
        youtubeService.userAgentFor(item.mediaId);
    // mpv must receive the UA exactly once. Sending it both as the `user-agent`
    // property and inside `http-header-fields` makes libmpv emit a duplicate
    // User-Agent header, which googlevideo answers with 403 / "Failed to open".
    final extraHeaders = Map<String, String>.fromEntries(
      allHeaders.entries.where((e) => e.key.toLowerCase() != 'user-agent'),
    );

    // Two attempts, not one. The first now costs nothing — the resolve already
    // set aside a progressive URL from the same manifest — so if that one is
    // also rejected it is worth spending a real resolve on the second.
    var fallbackAttempts = 0;
    var fallbackInFlight = false;
    Future<void> tryMuxedFallback() async {
      if (fallbackInFlight || fallbackAttempts >= 2) return;
      fallbackInFlight = true;
      fallbackAttempts++;
      try {
        await _runMuxedFallback(player, item, token, extraHeaders, resumeMs);
      } finally {
        fallbackInFlight = false;
      }
    }

    _mkSubs.add(player.stream.error.listen((error) {
      debugPrint('[mpv] error: $error');
      unawaited(tryMuxedFallback());
    }));

    try {
      final platform = player.platform;
      if (platform is mk.NativePlayer) {
        await platform.setProperty('user-agent', userAgent);
        await platform.setProperty('network-timeout', '15');

        // ffmpeg opens a network stream as one long-lived response by default
        // and does not reconnect if it dies. Seeking then issues a fresh
        // request that, on a throttled googlevideo connection, can stall with
        // nothing to time it out — which is the "skip forward and it hangs on
        // the spinner forever" behaviour.
        //
        // multiple_requests makes ffmpeg use keep-alive plus ranged requests
        // (what a seek actually needs), and the reconnect flags let it recover
        // from a dropped or refused connection instead of wedging.
        await platform.setProperty(
          'stream-lavf-o',
          'reconnect=1,'
          'reconnect_streamed=1,'
          'reconnect_on_network_error=1,'
          'reconnect_delay_max=5,'
          'multiple_requests=1',
        );

        // Serve backward seeks from memory instead of refetching, and keep the
        // stream seekable even when the server does not advertise it.
        await platform.setProperty('cache', 'yes');
        await platform.setProperty('demuxer-seekable-cache', 'yes');
        await platform.setProperty('demuxer-max-back-bytes', '${16 * 1024 * 1024}');
        await platform.setProperty('force-seekable', 'yes');

        // Keyframe seeks rather than exact ones. An exact seek has to decode
        // forward from the preceding keyframe, which over a slow network turns
        // a small skip into seconds of apparent buffering.
        await platform.setProperty('hr-seek', 'no');

        // Hardware decoding, copy-back rather than direct.
        //
        // The log carries "h264_mediacodec: Both surface and native_window are
        // NULL" on every single video. That is mpv trying the direct MediaCodec
        // path, which decodes into an Android Surface — but media_kit renders
        // through a texture and hands it no surface, so the decoder fails and
        // playback drops to software h264. On this device that is exactly the
        // stutter. `auto-copy` restricts mpv to methods that copy frames back
        // into normal memory, which is what a texture-based renderer needs.
        await platform.setProperty('hwdec', 'auto-copy');

        // Read much further ahead than mpv's ~1s default.
        //
        // Playback is landing on YouTube's progressive stream, and googlevideo
        // throttles those close to real time. With a one-second cushion every
        // dip in throughput is a visible stall; with twenty seconds buffered
        // the same dips are absorbed. demuxer-max-bytes (bufferSize above)
        // caps how much of this can actually be held.
        await platform.setProperty('demuxer-readahead-secs', '20');
        await platform.setProperty('cache-secs', '120');

        // When the cache does run dry, pause and refill properly instead of
        // resuming into another stall a moment later.
        await platform.setProperty('cache-pause-wait', '2');
        await platform.setProperty('cache-pause-initial', 'yes');

        // Where to begin. Set here, before open(), so mpv applies it during
        // load instead of us chasing it with a seek afterwards.
        await platform.setProperty(
          'start',
          resumeMs > 500 ? (resumeMs / 1000).toStringAsFixed(3) : 'none',
        );

        if (extraHeaders.isNotEmpty) {
          // NOTE: mpv splits this list on commas, so values containing commas
          // must never be pushed through here (that is why the UA is excluded).
          await platform.setProperty(
            'http-header-fields',
            extraHeaders.entries.map((e) => '${e.key}: ${e.value}').join(','),
          );
        }
      }

      YtLog.player('opening stream, separate audio=${item.audioUrl != null}');
      await player.open(mk.Media(item.path, httpHeaders: extraHeaders), play: false);

      if (item.audioUrl != null) {
        await player.setAudioTrack(mk.AudioTrack.uri(item.audioUrl!));
      }
      YtLog.player('initialized duration=${player.state.duration}');
    } catch (e) {
      unawaited(player.dispose());
      if (token != _playToken) return;
      state = state.copyWith(
        errorMessage: 'Could not play this stream. Check your connection and try again.',
        clearMkController: true,
        isPlaying: false,
      );
      return;
    }

    if (token != _playToken) {
      unawaited(player.dispose());
      return;
    }

    await player.setRate(state.speed == 0 ? 1.0 : state.speed);

    state = state.copyWith(
      mkPlayer: player,
      mkVideoController: videoController,
      clearVideoController: true,
      duration: player.state.duration,
      position: player.state.position,
      isPlaying: true,
    );

    _mkSubs.add(player.stream.position.listen((p) => _onMkTick(player, item.mediaId)));
    _mkSubs.add(player.stream.duration.listen((_) => _onMkTick(player, item.mediaId)));
    _mkSubs.add(player.stream.playing.listen((_) => _onMkTick(player, item.mediaId)));
    _mkSubs.add(player.stream.buffering.listen((_) => _onMkTick(player, item.mediaId)));
    _mkSubs.add(player.stream.completed.listen((completed) {
      if (completed && state.mkPlayer == player) _handleVideoCompletion();
    }));

    await player.play();
    // After play(), not before: the seek needs the demuxer to be running, and
    // doing it here means a failed adaptive open leaves the position intact
    // for the muxed fallback to apply instead. Not awaited — if this media is
    // one mpv is about to reject, its duration never arrives.
    unawaited(_seekWhenReady(player, resumeMs));

    // Warm the quality ladder so that tapping Quality or Download later opens
    // the panel from cache. Deliberately delayed: it fires several manifest
    // fetches whose JSON is parsed on this isolate, and doing that at the
    // moment playback is starting competes with the demuxer for both bandwidth
    // and CPU — which is what made the first seconds of a video feel rough.
    // By 12s the stream is settled and the user has not reached for the menu.
    _ladderWarmup?.cancel();
    _ladderWarmup = Timer(const Duration(seconds: 12), () {
      if (state.mkPlayer != player) return;
      unawaited(youtubeService.prefetchQualityLadder(item.mediaId));
    });

    _remoteWatchdog = Timer(const Duration(seconds: 25), () {
      if (state.mkPlayer != player) return;
      if (state.position > Duration.zero || state.duration > Duration.zero) return;
      _failRemote(
        player,
        'This video would not start streaming.\n'
        'YouTube may be blocking the stream — try another video.',
      );
    });
  }

  bool _completionHandled = false;

  void _onVideoTick(VideoPlayerController controller, String videoId) {
    if (state.videoController != controller) return;
    final value = controller.value;
    state = state.copyWith(
      position: value.position,
      duration: value.duration,
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
    );

    final atEnd = value.duration.inMilliseconds > 0 &&
        value.position.inMilliseconds >= value.duration.inMilliseconds - 250;
    if (atEnd && !value.isPlaying) {
      if (_completionHandled) return;
      _completionHandled = true;
      _handleVideoCompletion();
    } else {
      _completionHandled = false;
    }
  }

  void _onMkTick(mk.Player player, String videoId) {
    if (state.mkPlayer != player) return;
    final s = player.state;
    state = state.copyWith(
      position: s.position,
      duration: s.duration,
      isPlaying: s.playing,
      isBuffering: s.buffering,
    );
  }

  Future<void> _handleVideoCompletion() async {
    await mediaRepository.recordVideoProgress(
      state.current!.mediaId,
      state.duration.inMilliseconds,
      state.duration.inMilliseconds,
    );
    if (state.repeat == RepeatMode.one) {
      await seekTo(Duration.zero);
      await state.videoController?.play();
      await state.mkPlayer?.play();
      return;
    }
    if (settingsRepository.autoPlayNext && state.hasNext) {
      await skipNext();
    }
  }

  void _listenToAudioHandler() {
    _audioPlaybackSub = audioHandler.playbackState.listen((playbackState) {
      if (state.mode != PlaybackMode.audio) return;
      final queueIndex = playbackState.queueIndex;
      final indexChanged = !_audioEngineHoldsSingleItem &&
          queueIndex != null &&
          queueIndex >= 0 &&
          queueIndex < state.queue.length &&
          queueIndex != state.currentIndex;
      state = state.copyWith(
        isPlaying: playbackState.playing,
        isBuffering: playbackState.processingState == svc.AudioProcessingState.buffering ||
            playbackState.processingState == svc.AudioProcessingState.loading,
        position: playbackState.updatePosition,
        currentIndex: indexChanged ? queueIndex : state.currentIndex,
      );
      if (indexChanged) {
        final item = state.queue[queueIndex];
        unawaited(item.isVideo
            ? mediaRepository.recordVideoPlayed(item.mediaId)
            : mediaRepository.recordAudioPlayed(item.mediaId));
      }
      if (playbackState.processingState == svc.AudioProcessingState.completed) {
        _handleAudioCompletion();
      }
    });

    _audioMediaItemSub = audioHandler.mediaItem.listen((item) {
      if (state.mode != PlaybackMode.audio || item == null) return;
      state = state.copyWith(duration: item.duration ?? Duration.zero);
    });
  }

  Future<void> _handleAudioCompletion() async {
    if (state.repeat == RepeatMode.one) return;
    if (settingsRepository.autoPlayNext && !state.hasNext) {
      await audioHandler.pause();
    }
  }

  Future<void> _saveProgress() async {
    final item = state.current;
    if (item == null) return;
    if (item.isVideo) {
      await mediaRepository.recordVideoProgress(
        item.mediaId,
        state.position.inMilliseconds,
        state.duration.inMilliseconds,
      );
    } else {
      await mediaRepository.recordAudioProgress(item.mediaId, state.position.inMilliseconds);
    }
  }

  Future<void> _stopAudioEngine() async {
    if (state.mode == PlaybackMode.audio) {
      await _saveProgress();
      await audioHandler.pause();
    }
  }

  Future<void> stopAndClear() async {
    // Stops a background YouTube resolve from starting playback after the
    // user has already left the player screen.
    ++_resolveToken;
    ++_playToken;
    _remoteWatchdog?.cancel();
    await _saveProgress();
    await state.videoController?.dispose();
    _clearMkSubs();
    await state.mkPlayer?.dispose();
    await audioHandler.stop();
    await equalizerService.detach();
    await AudioVisualizerService.instance.detach();
    state = const PlayerUiState();
  }

  @override
  void dispose() {
    _audioPlaybackSub?.cancel();
    _audioMediaItemSub?.cancel();
    _progressSaveTimer?.cancel();
    _positionTicker?.cancel();
    _remoteWatchdog?.cancel();
    _ladderWarmup?.cancel();
    _clearMkSubs();
    state.videoController?.dispose();
    state.mkPlayer?.dispose();
    super.dispose();
  }
}