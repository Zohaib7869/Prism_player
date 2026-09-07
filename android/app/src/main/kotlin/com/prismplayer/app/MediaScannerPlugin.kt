package com.prismplayer.app

import android.content.Context
import android.database.Cursor
import android.provider.MediaStore
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Queries the device MediaStore for all playable video and audio files. This is a real,
 * incremental-friendly scan: callers pass `sinceEpochMs` (0 for a full scan) and only
 * files with DATE_MODIFIED after that point are returned, so the Dart-side repository
 * can upsert just the changed rows instead of re-scanning everything on every app launch.
 *
 * Channel: com.prismplayer.app/media_scanner
 */
class MediaScannerPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private val channelName = "com.prismplayer.app/media_scanner"

    fun registerWith(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "scanVideos" -> {
                val since = (call.argument<Number>("sinceEpochMs") ?: 0).toLong()
                result.success(scanVideos(since))
            }
            "scanAudio" -> {
                val since = (call.argument<Number>("sinceEpochMs") ?: 0).toLong()
                result.success(scanAudio(since))
            }
            else -> result.notImplemented()
        }
    }

    private fun scanVideos(sinceEpochMs: Long): List<Map<String, Any?>> {
        val items = mutableListOf<Map<String, Any?>>()
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
        val selection = "${MediaStore.Video.Media.DATE_MODIFIED} >= ?"
        val args = arrayOf((sinceEpochMs / 1000).toString())

        context.contentResolver.query(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI,
            projection,
            if (sinceEpochMs > 0) selection else null,
            if (sinceEpochMs > 0) args else null,
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
                val path = cursor.getString(dataCol) ?: continue
                if (!File(path).exists()) continue
                items.add(
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
        return items
    }

    private fun scanAudio(sinceEpochMs: Long): List<Map<String, Any?>> {
        val items = mutableListOf<Map<String, Any?>>()
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
        val selection = if (sinceEpochMs > 0)
            "${MediaStore.Audio.Media.DATE_MODIFIED} >= ? AND ${MediaStore.Audio.Media.IS_MUSIC} != 0"
        else
            "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        val args = if (sinceEpochMs > 0) arrayOf((sinceEpochMs / 1000).toString()) else null

        context.contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            selection,
            args,
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
                val path = cursor.getString(dataCol) ?: continue
                if (!File(path).exists()) continue
                val albumId = cursor.getLong(albumIdCol)
                items.add(
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
        return items
    }
}
