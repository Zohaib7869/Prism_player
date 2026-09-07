package com.prismplayer.app

import com.chaquo.python.Python
import org.json.JSONArray
import org.json.JSONObject

/**
 * SPIKE 2 + STEP 4 SCOPE (see prism-player-ytdlp-migration-architecture.md §5, §6, §20).
 *
 * Runs exactly the verified chain from §5 — nothing invented beyond it:
 *   Python.getInstance().getModule("yt_dlp")
 *   ytdlp.callAttr("YoutubeDL", opts)
 *   ydl.callAttr("extract_info", url, false)
 *   ydl.callAttr("sanitize_info", info)
 *   py.getModule("json").callAttr("dumps", clean)
 *
 * [extractDiagnostics] (spike 2) confirmed the free build (plain Python urllib, no
 * curl-cffi impersonation) can extract metadata without hitting YouTube's bot-check.
 * [getInfo] (step 4) reuses the same verified chain to return the full normalized
 * contract — title/duration/thumbnail/uploader/extractor + the format list — that
 * lib/models/youtube_native_info.dart and youtube_native_format.dart expect, for the
 * dynamic quality picker.
 *
 * Only normalized fields are pulled out of the JSON in Kotlin and returned; the full
 * sanitized dict is never sent across the MethodChannel or logged (§6: "raw logs
 * never cross"). No stream URL resolution or download-selector logic yet — that's
 * step 5+.
 *
 * Must be called off the main thread — extract_info is a blocking network call.
 *
 * IMPORTANT (found during spike 2 verification): the `opts` argument passed to
 * YoutubeDL() must be a genuine Python dict, not a Kotlin/Java Map handed to
 * callAttr() directly. Chaquopy wraps a Java Map in a proxy that only satisfies
 * Java's single-arg Map.get(key) — but yt_dlp's internals call the Python two-arg
 * dict.get(key, default) all over YoutubeDL.__init__ and its extractors, which
 * fails on that proxy with "TypeError: java.util.LinkedHashMap.get takes 1
 * argument (2 given)". Building opts via json.loads(...) produces a real dict and
 * avoids this entirely.
 */
object YtDlpExtractor {

    // Per §6: quiet/no_warnings/noplaylist/skip_download, socket_timeout, extract_flat=false.
    // Deliberately no user-agent, no client override, no extractor_args spoofing
    // (spec items 9, 49) — default/plain, to get an honest read on the free build.
    /**
     * Which YouTube player clients yt-dlp is allowed to use, in order.
     *
     * THIS IS THE KNOB TO TURN when downloads come back 403.
     *
     * Extraction succeeding and the resolved URL being *servable* are two
     * different things. With no PO token, several clients hand back correctly
     * signed URLs that googlevideo then refuses on the first byte — which is
     * exactly what the logs show for `android_vr`: extraction fine, download
     * 403, same 403 that mpv gets on the adaptive streams from an entirely
     * separate HTTP stack.
     *
     * Which clients serve without a PO token changes as YouTube tightens
     * things, so this is a list to try rather than a fixed answer. Reorder it,
     * or cut it down to a single entry, and check the `c=` parameter in the
     * URLs that come back in the download logs to see which one actually got
     * used.
     */
    // visionos leads deliberately. Verified 2026-09-07 against video
    // 89N21XzKKdM: tv_simply, android_vr and mweb all now return
    // "https formats require a GVS PO Token", which older yt-dlp builds
    // hand over anyway and GVS then answers with HTTP 403. visionos needs
    // no PO token. The rest are kept as fallbacks in case visionos is the
    // one YouTube breaks next.
    private val playerClients = listOf("visionos", "tv_simply", "web_embedded", "android_vr", "mweb")

    private val optsJson = JSONObject().apply {
        put("quiet", true)
        put("no_warnings", true)
        put("noplaylist", true)
        put("skip_download", true)
        put("socket_timeout", 15)
        put("extract_flat", false)
        put(
            "extractor_args",
            JSONObject().put(
                "youtube",
                JSONObject().put("player_client", JSONArray(playerClients)),
            ),
        )
    }.toString()

    /** Small diagnostic result — not the full sanitized info dict. */
    data class Diagnostics(
        val title: String?,
        val durationSeconds: Double?,
        val extractor: String?,
        val formatCount: Int
    )

    /**
     * Throws on any yt-dlp/Chaquopy failure (network, extractor, bot-check, etc.) —
     * the caller is responsible for classifying the exception message (§11 codes).
     */
    fun extractDiagnostics(url: String): Diagnostics {
        val obj = runExtractInfo(url)
        val formats = obj.optJSONArray("formats")
        return Diagnostics(
            title = obj.optStringOrNull("title"),
            durationSeconds = obj.optDoubleOrNull("duration"),
            extractor = obj.optStringOrNull("extractor"),
            formatCount = formats?.length() ?: 0
        )
    }

    /**
     * STEP 4: full metadata + normalized format list, matching the Dart contract in
     * youtube_native_info.dart / youtube_native_format.dart. Keys are camelCase to
     * match those models' primary field names.
     *
     * Throws on any yt-dlp/Chaquopy failure — the caller classifies the message
     * into §11 codes.
     */
    fun getInfo(url: String): Map<String, Any?> {
        val obj = runExtractInfo(url)
        return normalizeInfo(obj)
    }

    /** Runs the verified §5 chain and returns the sanitized info as a JSONObject. */
    private fun runExtractInfo(url: String): JSONObject {
        val py = Python.getInstance()
        val pyJson = py.getModule("json")
        // Genuine Python dict, built via json.loads — see class kdoc for why a
        // Kotlin/Java Map can't be passed to YoutubeDL() directly.
        val opts = pyJson.callAttr("loads", optsJson)

        val ytdlp = py.getModule("yt_dlp")
        val ydl = ytdlp.callAttr("YoutubeDL", opts)
        val info = ydl.callAttr("extract_info", url, false)
        val clean = ydl.callAttr("sanitize_info", info)
        val json = pyJson.callAttr("dumps", clean).toString()

        return JSONObject(json)
    }

    /**
     * STEP 5: resolves [formatSelector] (yt-dlp `-f` syntax, from
     * YoutubeFormatSelector.selectorForLabel — §8) against [url] and returns
     * the playable URL(s) + headers for that pick, matching the Dart contract
     * in youtube_native_stream_result.dart: {videoUrl, audioUrl?, combined,
     * quality, formatId, headers}.
     *
     * This is the actual fix for the 403s the legacy youtube_explode_dart
     * path hits: same verified free-build extract_info chain as [getInfo],
     * just with `format` set so yt-dlp resolves+authorizes one specific pick
     * (or an adaptive video+audio pair) instead of listing everything.
     *
     * Never cache the result on the Dart side (§8) — URLs are signed and
     * short-lived, so this must be called again for every playback/download
     * start, not reused from a previous resolve.
     *
     * Throws on any yt-dlp/Chaquopy failure — the caller classifies the
     * message into §11 codes, same as [getInfo].
     */
    fun getStreamUrls(url: String, formatSelector: String): Map<String, Any?> {
        val py = Python.getInstance()
        val pyJson = py.getModule("json")
        val optsWithFormat = JSONObject(optsJson).apply {
            // We only want yt-dlp to *resolve and authorize* the URLs, not
            // actually transfer bytes — the app's own SegmentedDownloader
            // does the transfer using the URLs handed back here.
            put("skip_download", true)
            put("format", formatSelector)
        }.toString()
        val opts = pyJson.callAttr("loads", optsWithFormat)

        val ytdlp = py.getModule("yt_dlp")
        val ydl = ytdlp.callAttr("YoutubeDL", opts)
        val info = ydl.callAttr("extract_info", url, false)
        val clean = ydl.callAttr("sanitize_info", info)
        val json = pyJson.callAttr("dumps", clean).toString()

        return normalizeStreamResult(JSONObject(json))
    }

    /**
     * With `format` set, extract_info resolves the selector itself. A
     * "+"-joined selector (adaptive video+audio, e.g. "bestvideo[...]+
     * bestaudio") populates `requested_formats` with the two chosen format
     * dicts, each already carrying its own authorized `url`. A single-format
     * selector (progressive, or an audio-only pick like "bestaudio/best")
     * has no `requested_formats` — the resolved `url` sits at the top level
     * of the sanitized info dict instead.
     */
    private fun normalizeStreamResult(obj: JSONObject): Map<String, Any?> {
        val requested = obj.optJSONArray("requested_formats")
        if (requested != null && requested.length() >= 2) {
            var videoFmt: JSONObject? = null
            var audioFmt: JSONObject? = null
            for (i in 0 until requested.length()) {
                val f = requested.optJSONObject(i) ?: continue
                if (hasVideo(f) && videoFmt == null) {
                    videoFmt = f
                } else if (hasAudio(f) && audioFmt == null) {
                    audioFmt = f
                }
            }
            // Fall back to positional if codec fields didn't disambiguate —
            // still two real, resolved formats either way.
            val video = videoFmt ?: requested.getJSONObject(0)
            val audio = audioFmt ?: requested.optJSONObject(1)

            return mapOf(
                "videoUrl" to video.optStringOrNull("url"),
                "audioUrl" to audio?.optStringOrNull("url"),
                "combined" to false,
                "quality" to qualityLabelOf(video),
                "formatId" to obj.optStringOrNull("format_id"),
                "headers" to headersOf(video)
            )
        }

        // Single resolved format — either a progressive (video+audio muxed)
        // stream, or a single audio-only pick. Either way there is exactly
        // one URL to fetch, so it goes in videoUrl and the caller (Dart
        // side) decides which DownloadTask field that maps to based on
        // whether the request was audio-only.
        val singleUrl = requested?.optJSONObject(0)?.optStringOrNull("url")
            ?: obj.optStringOrNull("url")
        if (singleUrl != null) {
            val source = requested?.optJSONObject(0) ?: obj
            return mapOf(
                "videoUrl" to singleUrl,
                "audioUrl" to null,
                "combined" to true,
                "quality" to qualityLabelOf(source),
                "formatId" to obj.optStringOrNull("format_id"),
                "headers" to headersOf(source)
            )
        }

        throw IllegalStateException("yt-dlp resolved no playable URL for this format selector")
    }

    private fun hasVideo(f: JSONObject): Boolean {
        val v = f.optStringOrNull("vcodec")
        return v != null && v != "none"
    }

    private fun hasAudio(f: JSONObject): Boolean {
        val a = f.optStringOrNull("acodec")
        return a != null && a != "none"
    }

    private fun qualityLabelOf(f: JSONObject): String {
        val height = f.optIntOrNull("height")
        if (height != null) return "${height}p"
        return f.optStringOrNull("format_note") ?: f.optStringOrNull("format_id") ?: ""
    }

    private fun headersOf(f: JSONObject): Map<String, String> {
        val headers = mutableMapOf<String, String>()
        val headersObj = f.optJSONObject("http_headers")
        if (headersObj != null) {
            val keys = headersObj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                headers[k] = headersObj.optString(k, "")
            }
        }
        return headers
    }

    private fun normalizeInfo(obj: JSONObject): Map<String, Any?> {
        val formatsArray = obj.optJSONArray("formats")
        val formats = mutableListOf<Map<String, Any?>>()
        if (formatsArray != null) {
            for (i in 0 until formatsArray.length()) {
                val f = formatsArray.optJSONObject(i) ?: continue
                formats.add(normalizeFormat(f))
            }
        }

        return mapOf(
            "id" to obj.optStringOrNull("id"),
            "title" to obj.optStringOrNull("title"),
            "durationSeconds" to obj.optDoubleOrNull("duration"),
            "thumbnailUrl" to obj.optStringOrNull("thumbnail"),
            "uploader" to obj.optStringOrNull("uploader"),
            "extractor" to obj.optStringOrNull("extractor"),
            "formats" to formats
        )
    }

    private fun normalizeFormat(f: JSONObject): Map<String, Any?> {
        val headers = mutableMapOf<String, String>()
        val headersObj = f.optJSONObject("http_headers")
        if (headersObj != null) {
            val keys = headersObj.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                headers[k] = headersObj.optString(k, "")
            }
        }
        return mapOf(
            "formatId" to f.optStringOrNull("format_id"),
            "ext" to f.optStringOrNull("ext"),
            "height" to f.optIntOrNull("height"),
            "width" to f.optIntOrNull("width"),
            "fps" to f.optDoubleOrNull("fps"),
            "vcodec" to f.optStringOrNull("vcodec"),
            "acodec" to f.optStringOrNull("acodec"),
            "abr" to f.optDoubleOrNull("abr"),
            "vbr" to f.optDoubleOrNull("vbr"),
            "tbr" to f.optDoubleOrNull("tbr"),
            "filesize" to f.optLongOrNull("filesize"),
            "filesizeApprox" to f.optLongOrNull("filesize_approx"),
            "formatNote" to f.optStringOrNull("format_note"),
            "httpHeaders" to headers
        )
    }

    // org.json's JSONObject.isNull(key) is true for both "missing" and "present but
    // JSON null" — these wrap that into idiomatic Kotlin nullable getters so callers
    // never need the has()+isNull() dance.
    private fun JSONObject.optStringOrNull(key: String): String? =
        if (isNull(key)) null else getString(key)

    private fun JSONObject.optDoubleOrNull(key: String): Double? =
        if (isNull(key)) null else getDouble(key)

    private fun JSONObject.optIntOrNull(key: String): Int? =
        if (isNull(key)) null else getInt(key)

    private fun JSONObject.optLongOrNull(key: String): Long? =
        if (isNull(key)) null else getLong(key)
}
