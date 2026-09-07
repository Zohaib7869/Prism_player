# Prism Player — YouTube downloader fix

**Read this first:** I have no Flutter SDK, no Dart, no Android toolchain and no
network to pub.dev or youtube.com in this environment. `flutter analyze` and
`flutter build apk` were **not run**. No APK was built and **no test case below
was executed on a device**. Everything here is from reading the source. Treat it
as a reviewed patch, not a verified one.

---

## 1. ROOT CAUSE

**Extraction and transfer happen in two different HTTP sessions.**

`YtDlpExtractor.getStreamUrls()` runs yt-dlp with `skip_download: true`, pulls
the resolved googlevideo URL out of the info dict, and hands the bare string
across the platform channel. `SegmentedDownloader` then fetches that string
with Dart's `HttpClient`.

That does not work for adaptive URLs. googlevideo binds them to the session
that minted them; replaying the same `User-Agent` from a different stack is not
enough. `download_manager.dart` already documents the observation without
naming the cause:

> "Extraction succeeding and the URL being fetchable are two different things:
> without a PO token these adaptive URLs are signed but not servable from this
> address."

The consequence, traced through `_run()`:

1. `_downloadStreams` → 403
2. `_looksExpired` → true → `_refreshUrls` → same yt-dlp path → same kind of URL
3. second attempt → 403
4. falls back to `youtubeService.progressiveDownloadOption` → **360p at best**,
   or `rethrow` → **failed** when no progressive exists

So every 720p/1080p download either silently collapses to 360p or fails.

**The fix was already designed and never built.** `YoutubeNativeService` has
declared `download()`, `cancelDownload()` and `downloadEvents` since step 6 was
specced. `YoutubeYtDlpPlugin.kt` implements neither method and registers **no
EventChannel at all**, so `download` hit `result.notImplemented()` and anything
subscribing to `ytdlp_events` would have thrown `MissingPluginException`.
Nothing in `lib/` ever called them, so the dead contract sat unnoticed.

### Ruled out by inspection (checked, not assumed)

| Suspicion | Verdict |
|---|---|
| `PrismPlayerApplication` not registered → `ytDlpInitialized` always false | **False.** `android:name=".PrismPlayerApplication"` is present in the manifest. |
| Platform channel name mismatch | **False.** All 8 channel names match Dart↔Kotlin. |
| Mux method/argument mismatch | **False.** `mux`/`extractAudio`/`cancelMux` and all arg keys match. |
| `rescanPath` not implemented natively | **False.** Handled in `SafeStorageBridgePlugin`. |
| `getStreamUrls` output keys ≠ `YoutubeNativeStreamResult.fromMap` | **False.** All six keys match. |
| Segmented downloader making parallel range requests | **Already fixed.** `connections = 1`. |

---

## 2. EXACT FILES CHANGED

### Created

| File | Destination |
|---|---|
| `YtDlpDownloader.kt` | `android/app/src/main/kotlin/com/prismplayer/app/` |
| `yt_log.dart` | `lib/core/services/` |
| `native_download_runner.dart` | `lib/core/services/` |

### Replaced

| File | Destination |
|---|---|
| `YoutubeYtDlpPlugin.kt` | `android/app/src/main/kotlin/com/prismplayer/app/` |

### Edited by hand (anchors below)

- `lib/core/services/download_manager.dart`
- `lib/providers/app_providers.dart`

---

## 3. WHAT WAS BROKEN

1. **`YoutubeYtDlpPlugin` registered no EventChannel.** One line missing in
   `registerWith`. Any subscriber to `downloadEvents` gets
   `MissingPluginException`.
2. **`download` / `cancel_download` fell through to `notImplemented()`.**
3. **The transfer used the wrong HTTP stack** (root cause above).
4. **Errors were string-matched on the raw exception.**
   `_readableError` greps for `'403'` in `e.toString()`, and `_run` then does
   `task.errorMessage!.contains('403')` — matching the *rendered user message*,
   not the error. It happens to work only because the message contains the
   digits.
5. **No diagnostics.** Three `debugPrint`s in the entire pipeline, one of which
   prints header *keys* only. Nothing between "user tapped" and "failed".
6. **`_headersFor` derives the User-Agent from `task.audioUrl`** even when the
   request being made is for `task.videoUrl`.

---

## 4. WHAT I FIXED

- `YtDlpDownloader.kt` performs the transfer inside yt-dlp, so the URL never
  leaves the session that signed it.
- Single-format selectors only. A `+` selector would make yt-dlp shell out to
  ffmpeg, which this AAR does not ship — that would have failed at the last
  step after transferring everything. Video and audio download as two jobs and
  join via the existing `MediaMuxPlugin`.
- Progress by polling the `.part` file, because `progress_hooks` needs a Python
  callable and there is no `src/main/python` in this project (no Chaquopy
  Gradle plugin).
- EventChannel registered; `download` and `cancel_download` implemented; event
  payload matches `YoutubeNativeDownloadEvent.fromMap` field for field.
- `YtDlpDownloader.classify` returns a normalized code, and
  `NativeDownloadFailure.userMessage` maps it to text. No raw yt-dlp string
  reaches the UI.
- Staged `[YT]` / `[DOWNLOAD]` / `[MUX]` / `[FILE]` logging on both sides of the
  channel, interleaving in one logcat.
- `YtLog.redact` strips URLs and `signature`/`pot`/`token`/`key`/`cookie`
  parameters. `YtLog.describeUrl` reports host + `c=` client + expiry state
  without the URL. Nothing logs a signed link.

---

## 5. EDITS TO APPLY BY HAND

### `lib/providers/app_providers.dart`

Add after `youtubeNativeServiceProvider`:

```dart
final nativeDownloadRunnerProvider = Provider<NativeDownloadRunner>((ref) {
  return NativeDownloadRunner(ref.watch(youtubeNativeServiceProvider));
});
```

Add the import, and pass it into `DownloadManager`:

```dart
    return DownloadManager(
      repository: ref.watch(downloadRepositoryProvider),
      youtubeService: ref.watch(youtubeServiceProvider),
      nativeService: ref.watch(youtubeNativeServiceProvider),
      nativeRunner: ref.watch(nativeDownloadRunnerProvider),   // ADD
      muxService: ref.watch(mediaMuxServiceProvider),
      scannerService: ref.watch(mediaScannerServiceProvider),
    );
```

### `lib/core/services/download_manager.dart`

**(a)** Add the field and constructor parameter alongside the existing ones:

```dart
  final NativeDownloadRunner nativeRunner;
```

**(b)** In `_downloadStreams`, the native branch replaces the
`SegmentedDownloader` calls. Anchor on this existing line:

```dart
    final headers = _headersFor(task);
```

Insert immediately **before** it:

```dart
    // Native path: let yt-dlp do the transfer so the URL stays inside the
    // session that signed it. Adaptive URLs 403 when fetched from any other
    // HTTP stack, which is what SegmentedDownloader was doing.
    if (task.nativeFormatSelector != null) {
      final watchUrl = YoutubeNativeDownloadResolver.watchUrlFor(task.videoId);
      final height = int.tryParse(task.qualityLabel.replaceAll('p', ''));

      if (task.isAudioOnly) {
        await nativeRunner.download(
          watchUrl: watchUrl,
          formatSelector: 'bestaudio',
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

      final videoSelector =
          height == null ? 'bestvideo' : 'bestvideo[height<=$height]';

      await nativeRunner.download(
        watchUrl: watchUrl,
        formatSelector: videoSelector,
        savePath: videoTemp,
        downloadId: '${task.id}-v',
        handle: handle,
        knownSize: task.videoBytes > 0 ? task.videoBytes : null,
        onProgress: (received, total) {
          task.receivedBytes = received;
          _emit(task);
        },
      );

      final videoDone = task.receivedBytes;

      await nativeRunner.download(
        watchUrl: watchUrl,
        formatSelector: 'bestaudio',
        savePath: audioTemp,
        downloadId: '${task.id}-a',
        handle: handle,
        knownSize: task.audioBytes > 0 ? task.audioBytes : null,
        onProgress: (received, total) {
          task.receivedBytes = videoDone + received;
          _emit(task);
        },
      );

      if (handle.isCancelled) throw const DownloadCancelled();

      task.status = DownloadStatus.muxing;
      _emit(task, persist: true);
      YtLog.mux('started video=$videoTemp audio=$audioTemp');

      await muxService.mux(
        videoPath: videoTemp,
        audioPath: audioTemp,
        outputPath: task.outputPath,
      );

      YtLog.mux('completed -> ${task.outputPath}');
      await _deleteQuietly(videoTemp);
      await _deleteQuietly(audioTemp);
      return;
    }
```

**(c)** In `_readableError`, add the classified case first so native failures
stop being string-matched:

```dart
  String _readableError(Object e) {
    if (e is NativeDownloadFailure) return e.userMessage;   // ADD
    final text = e.toString();
    // ...existing branches unchanged
```

**(d)** In `_run`'s catch block, replace the message-substring check:

```dart
      // was: if (task.errorMessage!.contains('403')) task.isStale = true;
      if (e is NativeDownloadFailure) {
        task.isStale = e.code == 'HTTP_403';
      } else if (e.toString().contains('403')) {
        task.isStale = true;
      }
```

**(e)** Imports to add:

```dart
import 'native_download_runner.dart';
import 'yt_log.dart';
```

---

## 6. COMPLETE DOWNLOAD FLOW (after the change)

```
videoId (from search result — no URL entry point exists yet)
  → DownloadOptionsSheet
  → YoutubeNativeDownloadResolver.listFormats
      → get_info            [YT] extraction started / formats count
  → user picks a quality label
  → DownloadManager.enqueue → _outputPath → Hive
  → _pump → _run
  → _downloadStreams
      → NativeDownloadRunner.download(bestvideo[height<=N])
          → YtDlpDownloader.downloadFormat   [DOWNLOAD] request started
          → poller emits size                [DOWNLOAD] progress
      → NativeDownloadRunner.download(bestaudio)
      → MediaMuxService.mux                  [MUX] started / completed
  → scannerService.rescan                    [FILE] final path
```

Note `getStreamUrls` is **no longer on the download path** — it is still used
for playback, which is a separate concern and was not touched.

---

## 7. TEST RESULTS

**None. Nothing was executed.** No Flutter SDK, no Android toolchain, and
pub.dev and youtube.com both return 403 from this sandbox.

All fifteen of your cases are unrun. Run them yourself with:

```bash
adb logcat -c
adb logcat | grep -E '\[YT\]|\[DOWNLOAD\]|\[MUX\]|\[FILE\]'
```

The first line that stops appearing is the failure point.

---

## 8. REMAINING LIMITATIONS

1. **Unverified.** Not compiled. Expect analyzer errors — most likely the
   `NativeDownloadRunner` constructor arg in `app_providers.dart` and missing
   imports.
2. **Chaquopy without its Gradle plugin.** `build.gradle.kts` notes the AAR is
   self-contained, but no Python source set exists, so `progress_hooks` is
   unavailable and progress is polled from the `.part` file. If
   `YtDlp.init()` fails on device, everything returns `YTDLP_INIT_FAILED` —
   check that first via `is_available`.
3. **Progress has no denominator** until yt-dlp writes enough to infer one.
   The bar may sit at an unknown percentage early on.
4. **Cancellation is cooperative.** yt-dlp's transfer loop is not interruptible
   from Kotlin; cancel is observed between polls, so a cancel can take up to
   ~500 ms and the current HTTP read completes first.
5. **`_baseDir()` writes to app-scoped external storage**
   (`Android/data/com.prismplayer.app/files/Prism Downloads`). Files there are
   deleted on uninstall and are not visible to other apps. If you want
   downloads in the public Movies/Music directories you need MediaStore inserts
   — I did not change this, since it is a product decision, not a bug.
6. **32-bit ARM devices are unsupported** — `abiFilters` is arm64-v8a + x86_64
   because the AAR ships no armeabi-v7a.
7. **Still no URL entry point.** Paste and share remain unimplemented; the
   parser from the previous turn is not wired up.

---

## 9. BUILD / RUN

```bash
flutter pub get
flutter analyze                     # expect errors; fix before proceeding
flutter build apk --debug
flutter install

adb logcat -c && adb logcat | grep -E '\[YT\]|\[DOWNLOAD\]|\[MUX\]|\[FILE\]'
```

Release builds additionally need R8 keeps for Chaquopy reflection — verify
`proguard-rules.pro` covers `com.chaquo.python.**` and
`dev.ffmpegkit_maintained.**` before shipping.
