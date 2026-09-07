package com.prismplayer.app

import android.content.Context
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.io.File
import kotlin.concurrent.thread

/**
 * Drives the "Scan Storage" screen. Unlike [MediaScannerPlugin] (which does a silent,
 * incremental MediaStore diff on every app launch), this does a full pass over every
 * video/audio row in MediaStore and streams real-time progress back to Dart: files
 * scanned so far, how many are actually media, and how much of the device's used
 * storage that represents — so the UI can show a live counter + percentage instead of
 * a blank spinner.
 *
 * Channel: com.prismplayer.app/storage_scan (EventChannel)
 *
 * Progress events: {"type":"progress", "filesScanned", "totalFiles", "mediaFound",
 *                    "bytesScanned", "totalStorageBytes", "percentFiles", "percentStorage",
 *                    "currentName"}
 * Final event:     {"type":"complete", "videos":[...], "audio":[...], "filesScanned", "mediaFound"}
 * Error event:     standard EventChannel error
 */
class StorageScanPlugin(private val context: Context) : EventChannel.StreamHandler {

    private val channelName = "com.prismplayer.app/storage_scan"
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var cancelled = false
    private var worker: Thread? = null

    fun registerWith(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        cancelled = false
        worker = thread(name = "prism-storage-scan") { runScan(events) }
    }

    override fun onCancel(arguments: Any?) {
        cancelled = true
        worker = null
    }

    private fun post(events: EventChannel.EventSink, map: Map<String, Any?>) {
        if (cancelled) return
        mainHandler.post { if (!cancelled) events.success(map) }
    }

    private fun runScan(events: EventChannel.EventSink) {
        try {
            val totalStorageBytes = usedStorageBytes()

            val videoTotal = countRows(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, null, null)
            val audioTotal = countRows(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                "${MediaStore.Audio.Media.IS_MUSIC} != 0",
                null
            )
            val totalFiles = (videoTotal + audioTotal).coerceAtLeast(1)

            var filesScanned = 0
            var mediaFound = 0
            var bytesScanned = 0L
            var lastEmitMs = 0L

            fun maybeEmit(currentName: String, force: Boolean = false) {
                val now = System.currentTimeMillis()
                if (!force && now - lastEmitMs < 120) return
                lastEmitMs = now
                val percentFiles = (filesScanned * 100.0 / totalFiles).coerceIn(0.0, 100.0)
                val percentStorage = if (totalStorageBytes > 0)
                    (bytesScanned * 100.0 / totalStorageBytes).coerceIn(0.0, 100.0) else 0.0
                post(
                    events,
                    mapOf(
                        "type" to "progress",
                        "filesScanned" to filesScanned,
                        "totalFiles" to totalFiles,
                        "mediaFound" to mediaFound,
                        "bytesScanned" to bytesScanned,
                        "totalStorageBytes" to totalStorageBytes,
                        "percentFiles" to percentFiles,
                        "percentStorage" to percentStorage,
                        "currentName" to currentName
                    )
                )
            }

            val videos = mutableListOf<Map<String, Any?>>()
            val audio = mutableListOf<Map<String, Any?>>()

            scanVideoRows { item ->
                if (cancelled) return@scanVideoRows
                videos.add(item)
                filesScanned++
                mediaFound++
                bytesScanned += (item["sizeBytes"] as? Long) ?: 0L
                maybeEmit(item["title"] as? String ?: "")
            }

            scanAudioRows { item ->
                if (cancelled) return@scanAudioRows
                audio.add(item)
                filesScanned++
                mediaFound++
                bytesScanned += (item["sizeBytes"] as? Long) ?: 0L
                maybeEmit(item["title"] as? String ?: "")
            }

            if (cancelled) return

            maybeEmit("", force = true)
            post(
                events,
                mapOf(
                    "type" to "complete",
                    "videos" to videos,
                    "audio" to audio,
                    "filesScanned" to filesScanned,
                    "mediaFound" to mediaFound
                )
            )
        } catch (e: Exception) {
            if (!cancelled) {
                mainHandler.post { events.error("scan_failed", e.message, null) }
            }
        }
    }

    private fun usedStorageBytes(): Long {
        return try {
            val stat = StatFs(Environment.getExternalStorageDirectory().path)
            val total = stat.totalBytes
            val available = stat.availableBytes
            (total - available).coerceAtLeast(0)
        } catch (e: Exception) {
            0L
        }
    }

    private fun countRows(uri: android.net.Uri, selection: String?, args: Array<String>?): Int {
        return try {
            context.contentResolver.query(uri, arrayOf(MediaStore.MediaColumns._ID), selection, args, null)
                ?.use { it.count } ?: 0
        } catch (e: Exception) {
            0
        }
    }

    private inline fun scanVideoRows(onItem: (Map<String, Any?>) -> Unit) {
        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DATA,
            MediaStore.Video.Media.DISPLAY_NAME,
            MediaStore.Video.Media.DURATION,
            MediaStore.Video.Media.SIZE,
            MediaStore.Video.Media.WIDTH,
            MediaStore.Video.Media.HEIGHT,
            MediaStore.Video.Media.DATE_MODIFIED,
            MediaStore.Video.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Video.Media.MIME_TYPE
        )
        context.contentResolver.query(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI, projection, null, null,
            "${MediaStore.Video.Media.DATE_MODIFIED} DESC"
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
            val durCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
            val wCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
            val hCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
            val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_MODIFIED)
            val bucketCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.BUCKET_DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)

            while (cursor.moveToNext()) {
                if (cancelled) return
                val path = cursor.getString(dataCol) ?: continue
                if (!File(path).exists()) continue
                onItem(
                    mapOf(
                        "id" to cursor.getLong(idCol).toString(),
                        "path" to path,
                        "title" to (cursor.getString(nameCol) ?: File(path).name),
                        "durationMs" to cursor.getLong(durCol),
                        "sizeBytes" to cursor.getLong(sizeCol),
                        "width" to cursor.getInt(wCol),
                        "height" to cursor.getInt(hCol),
                        "dateModifiedMs" to cursor.getLong(dateCol) * 1000,
                        "folderName" to (cursor.getString(bucketCol) ?: "Unknown"),
                        "mimeType" to (cursor.getString(mimeCol) ?: "video/*")
                    )
                )
            }
        }
    }

    private inline fun scanAudioRows(onItem: (Map<String, Any?>) -> Unit) {
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.ALBUM_ID,
            MediaStore.Audio.Media.GENRE,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_MODIFIED,
            MediaStore.Audio.Media.BUCKET_DISPLAY_NAME,
            MediaStore.Audio.Media.MIME_TYPE,
            MediaStore.Audio.Media.IS_MUSIC
        )
        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0", null,
            "${MediaStore.Audio.Media.DATE_MODIFIED} DESC"
        )?.use { cursor ->
            val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val albumIdCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
            val genreCol = try {
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.GENRE)
            } catch (e: IllegalArgumentException) {
                -1
            }
            val durCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_MODIFIED)
            val bucketCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.BUCKET_DISPLAY_NAME)
            val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.MIME_TYPE)

            while (cursor.moveToNext()) {
                if (cancelled) return
                val path = cursor.getString(dataCol) ?: continue
                if (!File(path).exists()) continue
                val albumId = cursor.getLong(albumIdCol)
                onItem(
                    mapOf(
                        "id" to cursor.getLong(idCol).toString(),
                        "path" to path,
                        "title" to (cursor.getString(titleCol) ?: cursor.getString(nameCol) ?: File(path).name),
                        "artist" to (cursor.getString(artistCol) ?: "Unknown Artist"),
                        "album" to (cursor.getString(albumCol) ?: "Unknown Album"),
                        "genre" to (if (genreCol >= 0) cursor.getString(genreCol) else null),
                        "albumArtUri" to "content://media/external/audio/albumart/$albumId",
                        "durationMs" to cursor.getLong(durCol),
                        "sizeBytes" to cursor.getLong(sizeCol),
                        "dateModifiedMs" to cursor.getLong(dateCol) * 1000,
                        "folderName" to (cursor.getString(bucketCol) ?: "Unknown"),
                        "mimeType" to (cursor.getString(mimeCol) ?: "audio/*")
                    )
                )
            }
        }
    }
}
