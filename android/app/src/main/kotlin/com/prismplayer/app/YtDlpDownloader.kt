package com.prismplayer.app

import android.util.Log
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Downloads ONE already-selected format using yt-dlp's own downloader.
 *
 * WHY THIS EXISTS
 * ---------------
 * The previous pipeline used yt-dlp only to *resolve* a URL and then handed
 * that bare string to Dart's HttpClient (SegmentedDownloader). That split is
 * the root cause of the 403s: googlevideo binds an adaptive URL to the session
 * that minted it, so replaying the same User-Agent from a different HTTP stack
 * is not sufficient. Extraction succeeding and the URL being fetchable are two
 * different things — a fact already recorded in DownloadManager's comments.
 *
 * Letting yt-dlp perform the transfer keeps resolution and fetch inside one
 * session, which is how yt-dlp is designed to be used and how every working
 * downloader does it.
 *
 * WHY SINGLE-FORMAT ONLY
 * ----------------------
 * [downloadFormat] deliberately refuses selectors containing '+'. A merging
 * selector makes yt-dlp shell out to ffmpeg, and this app's AAR bundles a
 * Python runtime, not an ffmpeg binary — a merge would fail at the last step
 * after transferring everything. Instead the caller downloads the video and
 * audio streams as two separate single-format jobs and joins them with the
 * existing MediaMuxPlugin (MediaMuxer), which already works.
 *
 * PROGRESS
 * --------
 * yt-dlp reports progress through `progress_hooks`, which expects a Python
 * callable. Chaquopy cannot pass a Kotlin lambda as one without a Python
 * source set, and this project has no Chaquopy Gradle plugin (see
 * app/build.gradle.kts), so there is no src/main/python to put a shim in.
 * Progress is therefore derived by polling the size of the part file yt-dlp is
 * writing. Less precise than a hook, and it needs no Python source.
 */
object YtDlpDownloader {

    private const val TAG = "YtDlpDownloader"
    private const val POLL_INTERVAL_MS = 500L

    /** Ids the Dart side has asked to cancel. Checked by the polling loop. */
    private val cancelled = ConcurrentHashMap.newKeySet<String>()

    class Cancelled : Exception("Download cancelled")

    fun requestCancel(downloadId: String) {
        cancelled.add(downloadId)
        Log.i(TAG, "[DOWNLOAD] cancel requested id=$downloadId")
    }

    fun clearCancel(downloadId: String) = cancelled.remove(downloadId)

    fun isCancelled(downloadId: String) = cancelled.contains(downloadId)

    /**
     * Transfers one format to [outputPath].
     *
     * @param formatSelector must resolve to a single format. A '+' selector is
     *   rejected rather than silently producing a file that never appears.
     * @param onProgress receives (receivedBytes, totalBytesOrZero).
     * @return the absolute path actually written.
     */
    fun downloadFormat(
        url: String,
        formatSelector: String,
        outputPath: String,
        downloadId: String,
        onProgress: (Long, Long) -> Unit
    ): String {
        require(!formatSelector.contains("+")) {
            "downloadFormat takes a single-format selector; '$formatSelector' " +
                "would require an ffmpeg merge, which is not available in this build"
        }

        clearCancel(downloadId)

        val out = File(outputPath)
        out.parentFile?.mkdirs()
        // yt-dlp appends its own extension when outtmpl has none, which would
        // put the file somewhere the caller is not looking. Pin the template to
        // the exact path the caller expects.
        val template = outputPath

        Log.i(TAG, "[DOWNLOAD] request started id=$downloadId fmt=$formatSelector")
        Log.i(TAG, "[FILE] target path=$outputPath")

        val py = Python.getInstance()
        val pyJson = py.getModule("json")

        val opts = JSONObject().apply {
            put("quiet", true)
            put("no_warnings", true)
            put("noplaylist", true)
            put("skip_download", false)
            put("format", formatSelector)
            put("outtmpl", template)
            put("socket_timeout", 30)
            put("retries", 5)
            put("fragment_retries", 5)
            // Resume a partial .part file rather than restarting the transfer.
            put("continuedl", true)
            put("nopart", false)
            // Never let yt-dlp try to post-process; there is no ffmpeg here.
            put("postprocessors", org.json.JSONArray())
            put(
                "extractor_args",
                JSONObject().put(
                    "youtube",
                    JSONObject().put(
                        "player_client",
                        org.json.JSONArray(listOf("visionos", "tv_simply", "web_embedded", "android_vr", "mweb"))
                    )
                )
            )
        }.toString()

        Log.d(TAG, "[YT] yt-dlp download config: format=$formatSelector retries=5")

        val poller = startProgressPoller(template, downloadId, onProgress)

        try {
            val pyOpts = pyJson.callAttr("loads", opts)
            val ytdlp = py.getModule("yt_dlp")
            val ydl = ytdlp.callAttr("YoutubeDL", pyOpts)

            Log.i(TAG, "[YT] yt-dlp download started id=$downloadId")
            // download=true — this is the whole point of this class.
            ydl.callAttr("extract_info", url, true)
        } finally {
            poller.interrupt()
        }

        if (isCancelled(downloadId)) {
            deletePartials(template)
            throw Cancelled()
        }

        val written = resolveWritten(template)
            ?: throw IllegalStateException("yt-dlp reported success but no file at $template")

        Log.i(TAG, "[DOWNLOAD] completed id=$downloadId bytes=${written.length()}")
        Log.i(TAG, "[FILE] final path=${written.absolutePath}")
        return written.absolutePath
    }

    /**
     * Watches the growing file and reports size. Runs as a daemon so a stuck
     * poll can never hold the process open.
     */
    private fun startProgressPoller(
        template: String,
        downloadId: String,
        onProgress: (Long, Long) -> Unit
    ): Thread {
        val thread = Thread {
            var lastReported = -1L
            try {
                while (!Thread.currentThread().isInterrupted) {
                    Thread.sleep(POLL_INTERVAL_MS)
                    if (isCancelled(downloadId)) {
                        Log.i(TAG, "[DOWNLOAD] cancel observed by poller id=$downloadId")
                        return@Thread
                    }
                    val size = currentSize(template)
                    if (size > 0 && size != lastReported) {
                        lastReported = size
                        onProgress(size, 0L)
                    }
                }
            } catch (_: InterruptedException) {
                // Normal shutdown once the transfer returns.
            } catch (e: Throwable) {
                Log.w(TAG, "[DOWNLOAD] progress poll stopped: ${e.message}")
            }
        }
        thread.isDaemon = true
        thread.name = "ytdlp-progress-$downloadId"
        thread.start()
        return thread
    }

    /** yt-dlp writes to `<path>.part` while transferring, then renames. */
    private fun currentSize(template: String): Long {
        val part = File("$template.part")
        if (part.exists()) return part.length()
        val done = File(template)
        return if (done.exists()) done.length() else 0L
    }

    private fun resolveWritten(template: String): File? {
        val exact = File(template)
        if (exact.exists() && exact.length() > 0) return exact
        // yt-dlp may still have appended a container extension despite outtmpl.
        val parent = exact.parentFile ?: return null
        val stem = exact.name
        return parent.listFiles()
            ?.firstOrNull { it.name.startsWith(stem) && !it.name.endsWith(".part") && it.length() > 0 }
    }

    private fun deletePartials(template: String) {
        listOf(File("$template.part"), File(template)).forEach {
            if (it.exists()) {
                val ok = it.delete()
                Log.d(TAG, "[FILE] cleanup ${it.name} deleted=$ok")
            }
        }
    }

    /** Extracts a normalized error code without leaking URLs or tokens. */
    fun classify(e: Throwable): Pair<String, String> {
        val raw = e.message ?: e.toString()
        val code = when {
            e is Cancelled -> "CANCELLED"
            raw.contains("Private video", true) -> "VIDEO_PRIVATE"
            raw.contains("age", true) && raw.contains("sign in", true) -> "VIDEO_AGE_RESTRICTED"
            raw.contains("Sign in to confirm", true) -> "LOGIN_REQUIRED"
            raw.contains("not available in your country", true) -> "VIDEO_GEO_RESTRICTED"
            raw.contains("Video unavailable", true) -> "VIDEO_UNAVAILABLE"
            raw.contains("Requested format is not available", true) -> "NO_FORMATS"
            raw.contains("429") -> "HTTP_429"
            raw.contains("403") -> "HTTP_403"
            raw.contains("ENOSPC", true) || raw.contains("No space", true) -> "STORAGE_FULL"
            raw.contains("Permission denied", true) -> "STORAGE_UNAVAILABLE"
            raw.contains("timed out", true) || raw.contains("Network", true) -> "NETWORK_ERROR"
            else -> "DOWNLOAD_FAILED"
        }
        // Strip anything URL-shaped so signed links never reach a log or the UI.
        val safe = raw.replace(Regex("https?://\\S+"), "<url>")
        return code to safe
    }
}
