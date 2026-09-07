import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Download cancelled';
}

class DownloadHandle {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class SegmentedDownloader {
  /// One connection, and no pre-flight probe either.
  ///
  /// The logs settled this. `contentLength` issues a `Range: bytes=0-0` GET
  /// against the URL and it *succeeds* — we know because the download then
  /// went on to split into three segments, which only happens when the total
  /// size came back. The very next requests, same URL and the same yt-dlp
  /// `http_headers` (User-Agent, Accept, Accept-Language, Sec-Fetch-Mode —
  /// confirmed in the log), are all answered 403.
  ///
  /// So this is not a credentials problem: one request works, several do not.
  /// googlevideo binds these URLs to a single sequential reader, which is
  /// exactly how yt-dlp itself fetches them. Raising [connections] above 1
  /// re-enables the segmented path below, and re-enables the 403s with it.
  static const int connections = 1;
  static const int _minSizeToSplit = 4 * 1024 * 1024;
  static const Duration _progressInterval = Duration(milliseconds: 400);

  /// Per-segment retry budget. A 403 here is nearly always throttling rather
  /// than a genuinely dead URL, and it clears within a second or two.
  static const int _maxRetriesPerSegment = 4;

  Map<String, String> headers;

  SegmentedDownloader({this.headers = const {}});

  HttpClient _newClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..idleTimeout = const Duration(seconds: 30)
    ..maxConnectionsPerHost = connections + 2
    ..autoUncompress = false;

  void _applyHeaders(HttpClientRequest request) {
    headers.forEach(request.headers.set);
  }

  Future<int?> contentLength(String url) async {
    final client = _newClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      
      // *** KEY FIX: Apply headers before the request ***
      _applyHeaders(request);
      
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final response = await request.close().timeout(const Duration(seconds: 15));
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      await response.drain<void>();

      if (response.statusCode == HttpStatus.partialContent && contentRange != null) {
        final total = int.tryParse(contentRange.split('/').last.trim());
        if (total != null && total > 0) return total;
      }
      if (response.statusCode == HttpStatus.ok) {
        final length = response.headers.contentLength;
        return length > 0 ? length : null;
      }
      return null;
    } catch (e) {
      debugPrint('[download] contentLength failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> download({
    required String url,
    required String savePath,
    required DownloadHandle handle,
    int? knownSize,
    void Function(int received, int total)? onProgress,
  }) async {
    // [knownSize] is only ever an estimate and must never drive the range
    // maths. On the native yt-dlp path it comes from the format *listing*
    // (`filesize_approx` for whichever format matched the label), while the
    // URL being fetched here comes from a later `getStreamUrls` call whose
    // selector can land on a different format entirely — the logs show the
    // real `clen` moving between resolves of the same quality. When the
    // estimate is larger than the file, the last segment's range starts past
    // the end and googlevideo answers 416 Range Not Satisfiable, forever: the
    // size marker never changes (it records the same wrong estimate every
    // time) so the stale parts are never cleared, and every retry and URL
    // refresh reproduces the identical bad range.
    //
    // Ask the server instead, and keep the estimate only as a denominator for
    // the progress bar when the server declines to say.
    final output = File(savePath);
    await output.parent.create(recursive: true);

    if (connections <= 1) {
      // Single sequential reader: the size comes out of the download's own
      // first response, so the URL is touched exactly once.
      await _downloadWhole(
        url: url,
        savePath: savePath,
        handle: handle,
        knownSize: knownSize,
        onProgress: onProgress,
      );
      return;
    }

    final reported = await contentLength(url);
    final total = reported ?? knownSize;
    if (handle.isCancelled) throw const DownloadCancelled();

    final sizeMarker = File('$savePath.size');
    if (total != null) {
      final previous = sizeMarker.existsSync() ? int.tryParse(await sizeMarker.readAsString()) : null;
      if (previous != null && previous != total) {
        await _clearParts(savePath);
      }
      await sizeMarker.writeAsString('$total');
    }

    final useSegments = total != null && total >= _minSizeToSplit;
    final segmentCount = useSegments ? connections : 1;

    final ranges = <List<int>>[];
    if (useSegments) {
      final chunk = (total / segmentCount).ceil();
      for (var i = 0; i < segmentCount; i++) {
        final start = i * chunk;
        final end = min(start + chunk - 1, total - 1);
        if (start <= end) ranges.add([start, end]);
      }
    } else {
      ranges.add([0, (total ?? 0) - 1]);
    }

    final received = List<int>.filled(ranges.length, 0);
    for (var i = 0; i < ranges.length; i++) {
      final part = File('$savePath.part$i');
      if (part.existsSync()) {
        final onDisk = await part.length();
        final expected = ranges[i][1] - ranges[i][0] + 1;
        received[i] = (total != null && onDisk > expected) ? 0 : onDisk;
        if (received[i] == 0 && onDisk > 0) await part.delete();
      }
    }

    Timer? ticker;
    if (onProgress != null) {
      ticker = Timer.periodic(_progressInterval, (_) {
        onProgress(received.fold<int>(0, (a, b) => a + b), total ?? 0);
      });
    }

    try {
      await Future.wait([
        for (var i = 0; i < ranges.length; i++)
          _downloadRange(
            url: url,
            partPath: '$savePath.part$i',
            start: ranges[i][0],
            end: total == null ? null : ranges[i][1],
            alreadyHave: received[i],
            handle: handle,
            onBytes: (n) => received[i] += n,
          ),
      ]);
    } finally {
      ticker?.cancel();
    }

    if (handle.isCancelled) throw const DownloadCancelled();
    onProgress?.call(received.fold<int>(0, (a, b) => a + b), total ?? 0);

    await _concatenate(savePath, ranges.length);
    await _clearParts(savePath);
  }

  /// Fetches the whole file over one connection, the way yt-dlp does.
  ///
  /// The total size is taken from this request's own `Content-Range` rather
  /// than from a separate probe, so a resumed or retried download still costs
  /// exactly one request against the URL.
  Future<void> _downloadWhole({
    required String url,
    required String savePath,
    required DownloadHandle handle,
    int? knownSize,
    void Function(int received, int total)? onProgress,
  }) async {
    final part = File('$savePath.part0');
    var have = part.existsSync() ? await part.length() : 0;
    var total = knownSize;
    Object? lastError;

    for (var attempt = 0; attempt <= _maxRetriesPerSegment; attempt++) {
      if (handle.isCancelled) throw const DownloadCancelled();

      if (attempt > 0) {
        final backoff = 400 * (1 << (attempt - 1));
        await Future<void>.delayed(
          Duration(milliseconds: backoff + Random().nextInt(250)),
        );
        if (handle.isCancelled) throw const DownloadCancelled();
      }

      final client = _newClient();
      IOSink? sink;
      try {
        final request = await client.getUrl(Uri.parse(url));
        _applyHeaders(request);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');

        final response = await request.close().timeout(const Duration(seconds: 30));

        if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
          // What is on disk does not belong to this file. Start over.
          await response.drain<void>();
          if (part.existsSync()) await part.delete();
          have = 0;
          continue;
        }
        if (response.statusCode != HttpStatus.ok &&
            response.statusCode != HttpStatus.partialContent) {
          await response.drain<void>();
          throw HttpException('Server returned ${response.statusCode}', uri: Uri.parse(url));
        }

        final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
        if (contentRange != null) {
          total = int.tryParse(contentRange.split('/').last.trim()) ?? total;
        } else if (response.contentLength > 0) {
          total = have + response.contentLength;
        }

        // A 200 means the server ignored the Range header and is sending the
        // file from the top, so anything already on disk would be duplicated.
        if (response.statusCode == HttpStatus.ok && have > 0) {
          if (part.existsSync()) await part.delete();
          have = 0;
        }

        sink = part.openWrite(mode: FileMode.append);
        var lastTick = DateTime.now();
        await for (final chunk in response) {
          if (handle.isCancelled) throw const DownloadCancelled();
          sink.add(chunk);
          have += chunk.length;
          if (onProgress != null &&
              DateTime.now().difference(lastTick) >= _progressInterval) {
            lastTick = DateTime.now();
            onProgress(have, total ?? 0);
          }
        }

        await sink.flush();
        await sink.close();
        sink = null;

        onProgress?.call(have, total ?? have);
        await _concatenate(savePath, 1);
        await _clearParts(savePath);
        return;
      } on DownloadCancelled {
        rethrow;
      } catch (e) {
        lastError = e;
        final retriable =
            e is HttpException || e is SocketException || e is TimeoutException;
        if (!retriable || attempt == _maxRetriesPerSegment) break;
        debugPrint('[download] retry ${attempt + 1} after: $e');
        // Resume from whatever actually reached disk.
        have = part.existsSync() ? await part.length() : 0;
      } finally {
        await sink?.flush();
        await sink?.close();
        client.close(force: true);
      }
    }

    throw lastError ?? HttpException('Download failed', uri: Uri.parse(url));
  }

  /// Downloads one byte range, retrying with backoff on throttling.
  ///
  /// Progress is not lost between attempts: whatever landed on disk becomes
  /// the new [alreadyHave], so a retry resumes rather than restarting.
  Future<void> _downloadRange({
    required String url,
    required String partPath,
    required int start,
    required int? end,
    required int alreadyHave,
    required DownloadHandle handle,
    required void Function(int) onBytes,
  }) async {
    var have = alreadyHave;
    Object? lastError;

    for (var attempt = 0; attempt <= _maxRetriesPerSegment; attempt++) {
      if (handle.isCancelled) throw const DownloadCancelled();
      if (end != null && have >= end - start + 1) return;

      if (attempt > 0) {
        // 400ms, 800ms, 1.6s, 3.2s — plus jitter so the segments that were
        // throttled together don't all come back at the same instant.
        final backoff = 400 * (1 << (attempt - 1));
        final jitter = Random().nextInt(250);
        await Future<void>.delayed(Duration(milliseconds: backoff + jitter));
        if (handle.isCancelled) throw const DownloadCancelled();
      }

      try {
        await _attemptRange(
          url: url,
          partPath: partPath,
          start: start,
          end: end,
          alreadyHave: have,
          handle: handle,
          onBytes: (n) {
            have += n;
            onBytes(n);
          },
        );
        return;
      } on DownloadCancelled {
        rethrow;
      } catch (e) {
        lastError = e;
        if (e is HttpException && e.toString().contains('416')) {
          // Range Not Satisfiable: whatever is on disk for this segment does
          // not line up with the file the server is serving. Resuming from
          // the same offset can only reproduce it, so start the segment over.
          final part = File(partPath);
          if (part.existsSync()) await part.delete();
          have = 0;
          if (attempt >= 1) break;
          continue;
        }
        final retriable = e is HttpException || e is SocketException || e is TimeoutException;
        // A 403 that comes back instantly, before a single byte has landed, is
        // a refusal rather than throttling — retrying it just delays the
        // caller's fallback. Throttling shows up as a 403 *after* some data
        // has already transferred, and that is still worth waiting out.
        final budget = (e is HttpException &&
                e.toString().contains('403') &&
                have == alreadyHave)
            ? 1
            : _maxRetriesPerSegment;
        if (!retriable || attempt >= budget) break;
        debugPrint('[download] segment retry ${attempt + 1} after: $e');
        // Re-read what actually made it to disk, so the retry resumes.
        final part = File(partPath);
        have = part.existsSync() ? await part.length() : 0;
      }
    }

    throw lastError ?? HttpException('Download failed', uri: Uri.parse(url));
  }

  Future<void> _attemptRange({
    required String url,
    required String partPath,
    required int start,
    required int? end,
    required int alreadyHave,
    required DownloadHandle handle,
    required void Function(int) onBytes,
  }) async {
    final client = _newClient();
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url));
      _applyHeaders(request);
      final from = start + alreadyHave;
      request.headers.set(
        HttpHeaders.rangeHeader,
        end == null ? 'bytes=$from-' : 'bytes=$from-$end',
      );

      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.partialContent &&
          response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('Server returned ${response.statusCode}', uri: Uri.parse(url));
      }

      final file = File(partPath);
      if (response.statusCode == HttpStatus.ok && alreadyHave > 0) {
        if (file.existsSync()) await file.delete();
      }

      sink = file.openWrite(mode: FileMode.append);
      await for (final chunk in response) {
        if (handle.isCancelled) throw const DownloadCancelled();
        sink.add(chunk);
        onBytes(chunk.length);
      }
    } finally {
      await sink?.flush();
      await sink?.close();
      client.close(force: true);
    }
  }

  Future<void> _concatenate(String savePath, int parts) async {
    final output = File(savePath);
    final sink = output.openWrite();
    try {
      for (var i = 0; i < parts; i++) {
        final part = File('$savePath.part$i');
        if (!part.existsSync()) continue;
        await sink.addStream(part.openRead());
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<void> _clearParts(String savePath) async {
    final dir = File(savePath).parent;
    if (!dir.existsSync()) return;
    final prefix = savePath.split('/').last;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (name.startsWith('$prefix.part') || name == '$prefix.size') {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> discard(String savePath) async {
    await _clearParts(savePath);
    final output = File(savePath);
    if (output.existsSync()) {
      try {
        await output.delete();
      } catch (_) {}
    }
  }
}