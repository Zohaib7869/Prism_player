package com.prismplayer.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.chaquo.python.Python
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Bridge to the bundled yt-dlp.
 *
 * CHANGED: previously this implemented resolution only (is_available,
 * get_version, extract_diagnostics, get_info, get_stream_urls) and registered
 * no EventChannel, so the `download` / `cancel_download` / `ytdlp_events`
 * contract that YoutubeNativeService has always declared hit
 * result.notImplemented() and MissingPluginException respectively.
 *
 * That gap was the reason downloads failed. Resolving a URL with yt-dlp and
 * then fetching it with a different HTTP client does not work for adaptive
 * googlevideo URLs: they are bound to the session that minted them, so the
 * fetch is refused with 403 no matter which headers are replayed. Doing the
 * transfer inside yt-dlp closes that gap.
 *
 * Channels:
 *   method: com.prismplayer.app/ytdlp
 *   event:  com.prismplayer.app/ytdlp_events
 */
class YoutubeYtDlpPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private companion object {
        const val TAG = "YtDlp"
        const val METHOD_CHANNEL = "com.prismplayer.app/ytdlp"
        const val EVENT_CHANNEL = "com.prismplayer.app/ytdlp_events"
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    /** Two lanes so a long transfer cannot block a quality-picker resolve. */
    private val resolveExecutor = Executors.newSingleThreadExecutor()
    private val downloadExecutor = Executors.newFixedThreadPool(2)

    @Volatile
    private var events: EventChannel.EventSink? = null

    fun registerWith(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)
        // Was missing entirely — without this, YoutubeNativeService.downloadEvents
        // throws MissingPluginException the moment anything subscribes.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        Log.i(TAG, "[YT] event channel attached")
    }

    override fun onCancel(arguments: Any?) {
        events = null
        Log.i(TAG, "[YT] event channel detached")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "[YT] method call: ${call.method}")
        when (call.method) {
            "is_available" -> result.success(PrismPlayerApplication.ytDlpInitialized)
            "get_version" -> getVersion(result)
            "extract_diagnostics" -> withUrlArg(call, result) { extractDiagnostics(it, result) }
            "get_info" -> withUrlArg(call, result) { getInfo(it, result) }
            "get_stream_urls" -> getStreamUrls(call, result)
            "download" -> startDownload(call, result)
            "cancel_download" -> cancelDownload(call, result)
            else -> {
                Log.w(TAG, "[YT] unimplemented method: ${call.method}")
                result.notImplemented()
            }
        }
    }

    // ---------------------------------------------------------------- download

    /**
     * Transfers one single-format selection to `outputTemplate`.
     *
     * Accepts the same argument names YoutubeNativeService.download already
     * sends: url, formatSelector, outputTemplate, downloadId. Returns as soon
     * as the job is accepted; progress and completion arrive on the event
     * channel keyed by downloadId.
     */
    private fun startDownload(call: MethodCall, result: MethodChannel.Result) {
        if (!requireInitialized(result)) return

        val url = call.argument<String>("url")
        val formatSelector = call.argument<String>("formatSelector")
        val outputTemplate = call.argument<String>("outputTemplate")
        val downloadId = call.argument<String>("downloadId")

        if (url.isNullOrBlank() || formatSelector.isNullOrBlank() ||
            outputTemplate.isNullOrBlank() || downloadId.isNullOrBlank()
        ) {
            Log.e(TAG, "[DOWNLOAD] rejected: missing arguments")
            result.error(
                "BAD_ARGS",
                "url, formatSelector, outputTemplate and downloadId are required",
                null
            )
            return
        }

        // Accept immediately; the Dart side is not awaiting completion here.
        result.success(true)
        emit(downloadId, "started")

        downloadExecutor.execute {
            try {
                val written = YtDlpDownloader.downloadFormat(
                    url = url,
                    formatSelector = formatSelector,
                    outputPath = outputTemplate,
                    downloadId = downloadId
                ) { received, total ->
                    emit(
                        downloadId,
                        "progress",
                        extra = mapOf(
                            "progress" to if (total > 0) received.toDouble() / total else null,
                            "receivedBytes" to received,
                            "totalBytes" to total
                        )
                    )
                }
                emit(downloadId, "completed", extra = mapOf("outputPath" to written))
            } catch (e: YtDlpDownloader.Cancelled) {
                Log.i(TAG, "[DOWNLOAD] cancelled id=$downloadId")
                emit(downloadId, "cancelled")
            } catch (e: Throwable) {
                val (code, message) = YtDlpDownloader.classify(e)
                Log.e(TAG, "[DOWNLOAD] failed id=$downloadId code=$code msg=$message")
                emit(
                    downloadId,
                    "failed",
                    extra = mapOf("errorCode" to code, "errorMessage" to message)
                )
            } finally {
                YtDlpDownloader.clearCancel(downloadId)
            }
        }
    }

    private fun cancelDownload(call: MethodCall, result: MethodChannel.Result) {
        val downloadId = call.argument<String>("downloadId")
        if (downloadId.isNullOrBlank()) {
            result.error("BAD_ARGS", "downloadId is required", null)
            return
        }
        YtDlpDownloader.requestCancel(downloadId)
        result.success(true)
    }

    /**
     * Posts one event to Dart. Shape matches YoutubeNativeDownloadEvent.fromMap
     * exactly: downloadId, type, progress?, etaSeconds?, outputPath?,
     * errorCode?, errorMessage?.
     */
    private fun emit(downloadId: String, type: String, extra: Map<String, Any?> = emptyMap()) {
        val payload = HashMap<String, Any?>()
        payload["downloadId"] = downloadId
        payload["type"] = type
        payload.putAll(extra)
        mainHandler.post {
            val sink = events
            if (sink == null) {
                Log.w(TAG, "[DOWNLOAD] event dropped (no listener): $type id=$downloadId")
            } else {
                sink.success(payload)
            }
        }
    }

    // -------------------------------------------------------------- resolution

    private inline fun withUrlArg(
        call: MethodCall,
        result: MethodChannel.Result,
        block: (String) -> Unit
    ) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("BAD_ARGS", "url is required", null)
            return
        }
        block(url)
    }

    private fun requireInitialized(result: MethodChannel.Result): Boolean {
        if (!PrismPlayerApplication.ytDlpInitialized) {
            val why = PrismPlayerApplication.ytDlpInitError
                ?: "YtDlp.init() has not completed successfully"
            Log.e(TAG, "[YT] yt-dlp unavailable: $why")
            result.error("YTDLP_INIT_FAILED", why, null)
            return false
        }
        return true
    }

    private fun getVersion(result: MethodChannel.Result) {
        if (!requireInitialized(result)) return
        resolveExecutor.execute {
            try {
                val version = Python.getInstance()
                    .getModule("yt_dlp.version")
                    .get("__version__")?.toString()
                Log.i(TAG, "[YT] yt-dlp version=$version")
                mainHandler.post { result.success(version) }
            } catch (e: Throwable) {
                mainHandler.post {
                    result.error("EXTRACTION_ERROR", e.message ?: e.toString(), null)
                }
            }
        }
    }

    private fun extractDiagnostics(url: String, result: MethodChannel.Result) {
        if (!requireInitialized(result)) return
        resolveExecutor.execute {
            try {
                val d = YtDlpExtractor.extractDiagnostics(url)
                Log.i(TAG, "[YT] diagnostics formats=${d.formatCount} extractor=${d.extractor}")
                mainHandler.post {
                    result.success(
                        mapOf(
                            "title" to d.title,
                            "durationSeconds" to d.durationSeconds,
                            "extractor" to d.extractor,
                            "formatCount" to d.formatCount
                        )
                    )
                }
            } catch (e: Throwable) {
                postClassifiedError(e, result)
            }
        }
    }

    private fun getInfo(url: String, result: MethodChannel.Result) {
        if (!requireInitialized(result)) return
        resolveExecutor.execute {
            try {
                Log.i(TAG, "[YT] extraction started")
                val info = YtDlpExtractor.getInfo(url)
                val count = (info["formats"] as? List<*>)?.size ?: 0
                Log.i(TAG, "[YT] extraction result received, formats count=$count")
                mainHandler.post { result.success(info) }
            } catch (e: Throwable) {
                postClassifiedError(e, result)
            }
        }
    }

    private fun getStreamUrls(call: MethodCall, result: MethodChannel.Result) {
        if (!requireInitialized(result)) return
        val url = call.argument<String>("url")
        val formatSelector = call.argument<String>("formatSelector")
        if (url.isNullOrBlank() || formatSelector.isNullOrBlank()) {
            result.error("BAD_ARGS", "url and formatSelector are required", null)
            return
        }
        resolveExecutor.execute {
            try {
                Log.i(TAG, "[YT] resolving selector=$formatSelector")
                val resolved = YtDlpExtractor.getStreamUrls(url, formatSelector)
                // Never log the URL itself — it is a signed credential.
                Log.i(
                    TAG,
                    "[YT] selected format=${resolved["formatId"]} " +
                        "quality=${resolved["quality"]} combined=${resolved["combined"]} " +
                        "directUrlAvailable=${resolved["videoUrl"] != null}"
                )
                mainHandler.post { result.success(resolved) }
            } catch (e: Throwable) {
                postClassifiedError(e, result)
            }
        }
    }

    private fun postClassifiedError(e: Throwable, result: MethodChannel.Result) {
        val (code, message) = YtDlpDownloader.classify(e)
        Log.e(TAG, "[YT] extraction failed code=$code msg=$message")
        mainHandler.post { result.error(code, message, null) }
    }
}
