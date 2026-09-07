import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/download_task.dart';
import '../../repositories/download_repository.dart';
import 'download_service.dart';
import 'media_mux_service.dart';
import 'media_scanner_service.dart';
import 'native_download_runner.dart';
import 'youtube_native_download_resolver.dart';
import 'youtube_native_service.dart';
import 'youtube_service.dart';
import 'yt_log.dart';

class DownloadManager extends StateNotifier<List<DownloadTask>> {
  final DownloadRepository repository;
  final YoutubeService youtubeService;
  final YoutubeNativeService nativeService;

  /// Performs transfers inside yt-dlp. See [NativeDownloadRunner] for why a
  /// resolved URL cannot simply be handed to [SegmentedDownloader].
  final NativeDownloadRunner nativeRunner;

  final MediaMuxService muxService;
  final MediaScannerService scannerService;

  static const int maxConcurrent = 2;
  static const _uuid = Uuid();

  final SegmentedDownloader _downloader =
      SegmentedDownloader(headers: kYoutubeStreamHttpHeaders);

  final Map<String, DownloadHandle> _handles = {};
  final Set<String> _running = {};

  Timer? _persistTimer;
  final Set<String> _dirty = {};

  DownloadManager({
    required this.repository,
    required this.youtubeService,
    required this.nativeService,
    required this.nativeRunner,
    required this.muxService,
    required this.scannerService,
  }) : super(repository.all()) {
    _recoverInterrupted();
    _persistTimer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
  }

  Future<Directory> _baseDir() async {
    final external = await getExternalStorageDirectory();
    final root = external ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/Prism Downloads');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _tempDir() async {
    final base = await _baseDir();
    final dir = Directory('${base.path}/.incomplete');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  String _sanitize(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final safe = cleaned.isEmpty ? 'video' : cleaned;
    return safe.length <= 80 ? safe : safe.substring(0, 80).trim();
  }

  Future<String> _outputPath({
    required String title,
    required String qualityLabel,
    required bool audioOnly,
  }) async {
    final base = await _baseDir();
    final folder = Directory('${base.path}/${audioOnly ? 'Audio' : 'Video'}');
    if (!folder.existsSync()) await folder.create(recursive: true);

    final extension = audioOnly ? 'm4a' : 'mp4';
    final stem = '${_sanitize(title)} (${qualityLabel.replaceAll(' ', '')})';

    var candidate = '${folder.path}/$stem.$extension';
    var counter = 1;
    while (File(candidate).existsSync()) {
      candidate = '${folder.path}/$stem ($counter).$extension';
      counter++;
    }
    return candidate;
  }

  Future<DownloadTask> enqueue({
    required String videoId,
    required String title,
    required YoutubeDownloadOption option,
    String? author,
    String? thumbnailUrl,
    int durationMs = 0,
  }) async {
    final task = DownloadTask(
      id: _uuid.v4(),
      videoId: videoId,
      title: title,
      author: author,
      thumbnailUrl: thumbnailUrl,
      isAudioOnly: option.audioOnly,
      qualityLabel: option.label,
      videoUrl: option.videoUrl,
      audioUrl: option.audioUrl,
      outputPath: await _outputPath(
        title: title,
        qualityLabel: option.label,
        audioOnly: option.audioOnly,
      ),
      videoBytes: option.videoBytes,
      audioBytes: option.audioBytes,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      durationMs: durationMs,
      headers: option.headers,
      nativeFormatSelector: option.nativeFormatSelector,
    );
    task.status = DownloadStatus.queued;

    await repository.put(task);
    state = [task, ...state];
    _pump();
    return task;
  }

  void pause(String id) {
    final task = _find(id);
    if (task == null) return;
    _handles[id]?.cancel();
    if (task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.paused;
      _emit(task, persist: true);
    }
  }

  void resumeTask(String id) {
    final task = _find(id);
    if (task == null) return;
    if (task.status != DownloadStatus.paused && task.status != DownloadStatus.failed) return;
    task.errorMessage = null;
    task.status = DownloadStatus.queued;
    _emit(task, persist: true);
    _pump();
  }

  Future<void> remove(String id, {bool deleteFile = true}) async {
    final task = _find(id);
    if (task == null) return;

    _handles[id]?.cancel();
    _running.remove(id);
    _handles.remove(id);
    _dirty.remove(id);

    if (deleteFile) {
      final temp = await _tempDir();
      await _downloader.discard('${temp.path}/$id.video');
      await _downloader.discard('${temp.path}/$id.audio');
      final output = File(task.outputPath);
      if (output.existsSync()) {
        try {
          await output.delete();
        } catch (e) {
          debugPrint('[download] could not delete ${task.outputPath}: $e');
        }
      }
    }

    await repository.delete(id);
    state = state.where((t) => t.id != id).toList();
    _pump();
  }

  void _recoverInterrupted() {
    var changed = false;
    for (final task in state) {
      if (task.status == DownloadStatus.running || task.status == DownloadStatus.muxing) {
        task.status = DownloadStatus.paused;
        unawaited(repository.put(task));
        changed = true;
      }
    }
    if (changed) state = [...state];
  }

  void _pump() {
    if (_running.length >= maxConcurrent) return;
    for (final task in state.reversed) {
      if (_running.length >= maxConcurrent) break;
      if (task.status != DownloadStatus.queued) continue;
      if (_running.contains(task.id)) continue;
      unawaited(_run(task));
    }
  }

  Future<void> _run(DownloadTask task) async {
    _running.add(task.id);
    final handle = DownloadHandle();
    _handles[task.id] = handle;

    task.status = DownloadStatus.running;
    task.errorMessage = null;
    _emit(task, persist: true);

    final temp = await _tempDir();
    final videoTemp = '${temp.path}/${task.id}.video';
    final audioTemp = '${temp.path}/${task.id}.audio';

    try {
      // A 403 part-way through is almost always an expired or throttled URL
      // rather than a dead video, so refresh the URLs and go again before
      // surfacing anything to the user.
      try {
        await _downloadStreams(task, handle, videoTemp, audioTemp);
      } on DownloadCancelled {
        rethrow;
      } catch (e) {
        if (!_looksExpired(e) || handle.isCancelled) rethrow;
        debugPrint('[download] ${task.title}: refreshing URLs after $e');
        task.isStale = true;
        task.receivedBytes = 0;
        _emit(task);

        try {
          await _downloadStreams(task, handle, videoTemp, audioTemp);
        } on DownloadCancelled {
          rethrow;
        } catch (e2) {
          if (!_looksExpired(e2) || handle.isCancelled) rethrow;

          // The native path was previously exempted from this fallback, on the
          // reasoning that yt-dlp's extraction avoids the bot-check and so a
          // 403 there had to be something else. The logs have since disproved
          // that. A yt-dlp-resolved ANDROID_VR URL is refused with 403 on the
          // very first request, with yt-dlp's own http_headers attached
          // (User-Agent, Accept, Accept-Language, Sec-Fetch-Mode — printed by
          // _headersFor), over a single connection, with no preceding probe.
          // Extraction succeeding and the URL being fetchable are two
          // different things: without a PO token these adaptive URLs are
          // signed but not servable from this address.
          //
          // The same split shows up in playback, through an entirely separate
          // HTTP stack: mpv is refused on every adaptive URL and succeeds on
          // the progressive one. Adaptive is what YouTube is refusing here,
          // not any particular client library. So the native path takes the
          // same fallback as the legacy one.

          // `progressiveDownloadOption` only ever returns a muxed
          // video+audio stream — YouTube publishes no progressive audio-only
          // equivalent. For an audio-only task the audio track is extracted
          // out of that muxed file afterwards, rather than saving a 360p
          // *video* under a ".m4a" path.

          // YouTube currently only publishes progressive up to 360p, so this
          // is very likely a real drop from whatever quality the user picked —
          // reflect that in qualityLabel rather than leaving the UI and
          // filename claiming the originally requested, undelivered quality.
          final progressive =
              await youtubeService.progressiveDownloadOption(task.videoId);
          if (progressive == null) rethrow;

          debugPrint('[download] ${task.title}: falling back to progressive '
              '${progressive.label} after repeated 403s');
          task.videoUrl = null;
          task.audioUrl = progressive.audioUrl;
          task.videoBytes = 0;
          task.audioBytes = progressive.audioBytes;
          task.qualityLabel = task.isAudioOnly
              ? task.qualityLabel
              : progressive.label;
          task.receivedBytes = 0;
          task.isStale = false;
          // Progressive URLs come from youtube_explode's manifest, so they
          // need that client's headers, not yt-dlp's.
          task.headers = null;
          task.nativeFormatSelector = null;
          _emit(task, persist: true);

          await _deleteQuietly(videoTemp);
          await _deleteQuietly(audioTemp);

          if (task.isAudioOnly) {
            // Fetch the muxed file to a temp path, then keep only its audio
            // track. A stream copy, so no re-encode and no quality loss.
            final progressiveDownloader =
                SegmentedDownloader(headers: _headersFor(task));
            await progressiveDownloader.download(
              url: task.audioUrl,
              savePath: audioTemp,
              handle: handle,
              knownSize: task.audioBytes > 0 ? task.audioBytes : null,
              onProgress: (received, total) {
                task.receivedBytes = received;
                _emit(task);
              },
            );
            if (handle.isCancelled) throw const DownloadCancelled();
            await muxService.extractAudio(
              sourcePath: audioTemp,
              outputPath: task.outputPath,
            );
            await _deleteQuietly(audioTemp);
          } else {
            await _downloadStreams(task, handle, videoTemp, audioTemp);
          }
        }
      }

      task.status = DownloadStatus.completed;
      task.completedAtMs = DateTime.now().millisecondsSinceEpoch;
      task.receivedBytes = task.totalBytes;
      _emit(task, persist: true);

      unawaited(scannerService.rescan(task.outputPath));
    } on DownloadCancelled {
      task.status = DownloadStatus.paused;
      _emit(task, persist: true);
    } catch (e) {
      debugPrint('[download] ${task.title} failed: $e');
      task.status = DownloadStatus.failed;
      task.errorMessage = _readableError(e);

      // Mark stale off the classified code where we have one. The old check
      // matched '403' against the rendered *user message*, not the error, and
      // only worked by coincidence of that message containing the digits.
      if (e is NativeDownloadFailure) {
        task.isStale = e.code == 'HTTP_403';
      } else if (e.toString().contains('403')) {
        task.isStale = true;
      }

      _emit(task, persist: true);
    } finally {
      _running.remove(task.id);
      _handles.remove(task.id);
      _pump();
    }
  }

  /// Headers to fetch this task's URLs with.
  ///
  /// `task.headers` comes from yt-dlp's `http_headers` for the chosen format,
  /// and those URLs are signed for exactly that User-Agent. Two things have to
  /// be guarded here. An *empty* map is not the same as "no headers set", but
  /// `??` treats it as a real value, so a format whose `http_headers` came
  /// back empty produced requests with no User-Agent at all — which
  /// googlevideo answers with 403 on the very first byte of every segment.
  /// And a header map that exists but happens to omit the User-Agent has the
  /// same effect, so one is filled in to match the client that minted the URL.
  Map<String, String> _headersFor(DownloadTask task) {
    final fromTask = task.headers;
    if (fromTask == null || fromTask.isEmpty) {
      return youtubeService.streamHeadersFor(task.videoId);
    }
    final hasUserAgent = fromTask.keys.any((k) => k.toLowerCase() == 'user-agent');
    if (hasUserAgent) return fromTask;
    return {
      ...fromTask,
      'user-agent': _userAgentForUrl(task.audioUrl),
    };
  }

  /// googlevideo URLs name the client that signed them in `c=`. Matching it is
  /// what keeps the signature valid.
  String _userAgentForUrl(String url) {
    if (url.contains('c=ANDROID_VR')) {
      return 'com.google.android.apps.youtube.vr.oculus/1.56.21 '
          '(Linux; U; Android 12; en_US; Quest 3 Build/SQ3A.220605.009.A1) gzip';
    }
    if (url.contains('c=IOS')) {
      return 'com.google.ios.youtube/20.10.4 '
          '(iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
    }
    return 'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  }

  /// True for the failure modes that a fresh set of stream URLs would fix.
  bool _looksExpired(Object e) {
    final text = e.toString();
    return text.contains('403') || text.contains('410') || text.contains('401');
  }

  Future<void> _downloadStreams(
    DownloadTask task,
    DownloadHandle handle,
    String videoTemp,
    String audioTemp,
  ) async {
    // Native path: yt-dlp performs the transfer itself, so the resolved URL
    // never leaves the session that signed it. Fetching an adaptive
    // googlevideo URL from any other HTTP stack is refused with 403 no matter
    // which headers are replayed, which is what the SegmentedDownloader path
    // below was doing. Runs before the isStale refresh because yt-dlp
    // re-resolves internally, making a separate getStreamUrls call redundant.
    if (task.nativeFormatSelector != null) {
      await _downloadViaNative(task, handle, videoTemp, audioTemp);
      return;
    }

    if (task.isStale) await _refreshUrls(task);

    // Headers must match whatever minted these URLs — a googlevideo URL
    // signed for one client/User-Agent 403s under another. Native
    // (yt-dlp-resolved) tasks carry their own exact headers; legacy tasks
    // fall back to the per-client header set youtube_explode_dart used.
    final headers = _headersFor(task);
    debugPrint('[download] ${task.title}: headers = ${headers.keys.join(", ")}');
    final downloader = SegmentedDownloader(headers: headers);

    if (task.videoUrl == null) {
      await downloader.download(
        url: task.audioUrl,
        savePath: task.outputPath,
        handle: handle,
        knownSize: task.audioBytes > 0 ? task.audioBytes : null,
        onProgress: (received, total) {
          if (total > 0 && task.audioBytes != total) task.audioBytes = total;
          task.receivedBytes = received;
          _emit(task);
        },
      );
    } else {
      var videoDone = 0;

      await downloader.download(
        url: task.videoUrl!,
        savePath: videoTemp,
        handle: handle,
        knownSize: task.videoBytes > 0 ? task.videoBytes : null,
        onProgress: (received, total) {
          if (total > 0 && task.videoBytes != total) task.videoBytes = total;
          videoDone = received;
          task.receivedBytes = received;
          _emit(task);
        },
      );
      videoDone = task.videoBytes;

      await downloader.download(
        url: task.audioUrl,
        savePath: audioTemp,
        handle: handle,
        knownSize: task.audioBytes > 0 ? task.audioBytes : null,
        onProgress: (received, total) {
          if (total > 0 && task.audioBytes != total) task.audioBytes = total;
          task.receivedBytes = videoDone + received;
          _emit(task);
        },
      );

      if (handle.isCancelled) throw const DownloadCancelled();

      task.status = DownloadStatus.muxing;
      _emit(task, persist: true);

      await muxService.mux(
        videoPath: videoTemp,
        audioPath: audioTemp,
        outputPath: task.outputPath,
      );

      await _deleteQuietly(videoTemp);
      await _deleteQuietly(audioTemp);
    }
  }

  /// Transfers this task through yt-dlp, one single-format job per stream.
  ///
  /// A '+' selector is deliberately never used: it would make yt-dlp shell out
  /// to ffmpeg, which this build does not ship, and would fail at the merge
  /// after transferring everything. Video and audio come down separately and
  /// are joined by [MediaMuxService], which already works.
  Future<void> _downloadViaNative(
    DownloadTask task,
    DownloadHandle handle,
    String videoTemp,
    String audioTemp,
  ) async {
    final watchUrl = YoutubeNativeDownloadResolver.watchUrlFor(task.videoId);
    final height = int.tryParse(task.qualityLabel.replaceAll(RegExp(r'[^0-9]'), ''));

    if (task.isAudioOnly) {
      YtLog.download('audio-only job for ${task.videoId}');
      await nativeRunner.download(
        watchUrl: watchUrl,
        formatSelector: 'bestaudio[acodec^=mp4a]/bestaudio[ext=m4a]/bestaudio',
        savePath: task.outputPath,
        downloadId: '${task.id}-a',
        handle: handle,
        knownSize: task.audioBytes > 0 ? task.audioBytes : null,
        onProgress: (received, total) {
          task.receivedBytes = received;
          _emit(task);
        },
      );
      return;
    }

    // H.264 is requested ahead of anything else because MediaMuxer cannot
    // write AV1 or Opus into an MP4 container. Without this the muxer throws
    // on addTrack after a fully successful download — the selector that was
    // resolving to 398+251 (AV1 + Opus) would have failed at the last step.
    final videoSelector = height == null
        ? 'bestvideo[vcodec^=avc1]/bestvideo'
        : 'bestvideo[vcodec^=avc1][height<=$height]/bestvideo[height<=$height]';
    YtLog.download('video job selector=$videoSelector');

    await nativeRunner.download(
      watchUrl: watchUrl,
      formatSelector: videoSelector,
      savePath: videoTemp,
      downloadId: '${task.id}-v',
      handle: handle,
      knownSize: task.videoBytes > 0 ? task.videoBytes : null,
      onProgress: (received, total) {
        if (total > 0 && task.videoBytes != total) task.videoBytes = total;
        task.receivedBytes = received;
        _emit(task);
      },
    );

    if (handle.isCancelled) throw const DownloadCancelled();
    // Overall progress is video-so-far + audio-so-far against the combined
    // total, so the bar advances once across both jobs instead of resetting.
    final videoDone = task.receivedBytes;
    YtLog.download('video stream done: $videoDone bytes');

    YtLog.download('audio job selector=bestaudio[acodec^=mp4a] chain');
    await nativeRunner.download(
      watchUrl: watchUrl,
      formatSelector: 'bestaudio[acodec^=mp4a]/bestaudio[ext=m4a]/bestaudio',
      savePath: audioTemp,
      downloadId: '${task.id}-a',
      handle: handle,
      knownSize: task.audioBytes > 0 ? task.audioBytes : null,
      onProgress: (received, total) {
        if (total > 0 && task.audioBytes != total) task.audioBytes = total;
        task.receivedBytes = videoDone + received;
        _emit(task);
      },
    );

    if (handle.isCancelled) throw const DownloadCancelled();

    task.status = DownloadStatus.muxing;
    _emit(task, persist: true);
    YtLog.mux('started -> ${task.outputPath}');

    await muxService.mux(
      videoPath: videoTemp,
      audioPath: audioTemp,
      outputPath: task.outputPath,
    );

    YtLog.mux('completed');
    await _deleteQuietly(videoTemp);
    await _deleteQuietly(audioTemp);
  }

  Future<void> _refreshUrls(DownloadTask task) async {
    task.isStale = false;

    if (task.nativeFormatSelector != null) {
      // Re-resolve through the same yt-dlp selector that produced this
      // task's original URLs — same reasoning as _run()'s guard above:
      // this path isn't the one that 403s, so a fresh resolve is the right
      // fix on its own, no legacy fallback needed.
      final res = await nativeService.getStreamUrls(
        YoutubeNativeDownloadResolver.watchUrlFor(task.videoId),
        task.nativeFormatSelector!,
      );
      final isAdaptivePair = !task.isAudioOnly && !res.combined && res.audioUrl != null;
      task.videoUrl = isAdaptivePair ? res.videoUrl : null;
      task.audioUrl = isAdaptivePair ? res.audioUrl! : res.videoUrl;
      task.headers = res.headers;
      _emit(task, persist: true);
      return;
    }

    // Legacy youtube_explode_dart path — bypass any cached manifests by
    // forcing a fresh resolve.
    final options = await youtubeService.getDownloadOptions(task.videoId);
    if (options.isEmpty) {
      throw StateError('This video is no longer available for download.');
    }
    final match = options.firstWhere(
      (o) => o.label == task.qualityLabel && o.audioOnly == task.isAudioOnly,
      orElse: () => options.firstWhere(
        (o) => o.audioOnly == task.isAudioOnly,
        orElse: () => options.first,
      ),
    );
    task.videoUrl = match.videoUrl;
    task.audioUrl = match.audioUrl;
    _emit(task, persist: true);
  }

  String _readableError(Object e) {
    // Native failures already carry a normalized code — use it rather than
    // grepping a raw exception string.
    if (e is NativeDownloadFailure) return e.userMessage;
    final text = e.toString();
    if (text.contains('403')) {
      return 'YouTube refused the download link. Try again, or pick a different quality.';
    }
    if (e is SocketException || text.contains('Failed host lookup')) {
      return 'No internet connection.';
    }
    if (text.contains('No space') || text.contains('ENOSPC')) {
      return 'Not enough free storage.';
    }
    if (text.contains('TimeoutException')) {
      return 'The connection timed out.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  Future<void> _deleteQuietly(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      await file.delete();
    } catch (_) {}
  }

  DownloadTask? _find(String id) {
    for (final task in state) {
      if (task.id == id) return task;
    }
    return null;
  }

  void _emit(DownloadTask task, {bool persist = false}) {
    if (persist) {
      unawaited(repository.put(task));
      _dirty.remove(task.id);
    } else {
      _dirty.add(task.id);
    }
    if (mounted) state = [...state];
  }

  void _flush() {
    if (_dirty.isEmpty) return;
    for (final id in _dirty.toList()) {
      final task = _find(id);
      if (task != null) unawaited(repository.put(task));
    }
    _dirty.clear();
  }

  List<DownloadTask> get active => state.where((t) => t.isPending).toList();
  List<DownloadTask> get completedVideos => state
      .where((t) => t.status == DownloadStatus.completed && !t.isAudioOnly)
      .toList();
  List<DownloadTask> get completedAudio => state
      .where((t) => t.status == DownloadStatus.completed && t.isAudioOnly)
      .toList();

  @override
  void dispose() {
    _persistTimer?.cancel();
    for (final handle in _handles.values) {
      handle.cancel();
    }
    _flush();
    super.dispose();
  }
}