package com.prismplayer.app

import android.content.Context
import android.media.MediaMetadataRetriever
import android.media.MediaScannerConnection
import android.os.Handler
import android.os.Looper
import android.util.Size
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/**
 * Handles the native filesystem/MediaStore side of file management (rename, delete,
 * rescan-after-change) and generates on-disk JPEG thumbnails for videos so the Dart
 * side never has to hold raw bitmaps in memory for the whole library at once.
 *
 * Named "SafeStorageBridge" because it is also the bridge the Safe Media feature uses
 * to force a MediaStore rescan after a file's visibility metadata changes, without ever
 * moving or renaming the underlying file (Safe Media hides files at the app-database
 * level only, per spec — the file itself is left untouched).
 *
 * Channel: com.prismplayer.app/file_ops
 */
class SafeStorageBridgePlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private val channelName = "com.prismplayer.app/file_ops"

    // Thumbnail generation (MediaMetadataRetriever decode + bitmap compress + file
    // write) is genuinely slow — tens to hundreds of ms per video. The method
    // channel handler runs on the platform/UI thread by default, so doing this
    // work inline used to block the UI thread once per video card, which is
    // exactly what showed up as the video grid/list "lagging". Every other
    // method on this channel is cheap (simple file/MediaStore calls) and stays
    // on the calling thread; only generateVideoThumbnail is moved off it.
    private val thumbnailExecutor = Executors.newFixedThreadPool(2)
    private val mainHandler = Handler(Looper.getMainLooper())

    fun registerWith(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "renameFile" -> {
                    val path = call.argument<String>("path")!!
                    val newName = call.argument<String>("newName")!!
                    result.success(renameFile(path, newName))
                }
                "deleteFile" -> {
                    val path = call.argument<String>("path")!!
                    result.success(deleteFile(path))
                }
                "rescanPath" -> {
                    val path = call.argument<String>("path")!!
                    rescan(path)
                    result.success(true)
                }
                "generateVideoThumbnail" -> {
                    val path = call.argument<String>("path")!!
                    val outputPath = call.argument<String>("outputPath")!!
                    val maxWidth = call.argument<Int>("maxWidth") ?: 512
                    // Off the platform thread — see thumbnailExecutor comment above.
                    thumbnailExecutor.execute {
                        val thumbPath = try {
                            generateVideoThumbnail(path, outputPath, maxWidth)
                        } catch (e: Exception) {
                            null
                        }
                        mainHandler.post { result.success(thumbPath) }
                    }
                }
                "getAlbumArtBytes" -> {
                    val uri = call.argument<String>("uri")!!
                    result.success(getAlbumArtBytes(uri))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("FILE_OPS_ERROR", e.message, null)
        }
    }

    private fun renameFile(path: String, newName: String): String? {
        val src = File(path)
        if (!src.exists()) return null
        val dest = File(src.parentFile, newName)
        val ok = src.renameTo(dest)
        if (ok) {
            rescan(path)
            rescan(dest.absolutePath)
            return dest.absolutePath
        }
        return null
    }

    private fun deleteFile(path: String): Boolean {
        val file = File(path)
        val ok = if (file.exists()) file.delete() else false
        rescan(path)
        return ok
    }

    private fun rescan(path: String) {
        MediaScannerConnection.scanFile(context, arrayOf(path), null, null)
    }

    /** Reads MediaStore album-art bytes (e.g. content://media/external/audio/albumart/N)
     * so the Dart side can render it with Image.memory — Flutter's Image.file can't
     * resolve content:// URIs directly. Returns null if the track has no embedded art. */
    /**
     * MediaStore album-art URIs frequently resolve to garbage: zero-byte
     * placeholders, HEIF/WEBP variants this device's decoder rejects, or raw
     * ID3 frames with a leading MIME header. Handing those straight to Dart's
     * Image.memory produced a stream of
     * "FlutterImageDecoderImplDefault: Failed to decode image ... unimplemented"
     * errors in logcat. Decode-check the bytes here and, when they are valid,
     * hand back a normalised JPEG the Flutter decoder always understands.
     * Undecodable art returns null so the UI shows its themed fallback icon.
     */
    private fun getAlbumArtBytes(uriString: String): ByteArray? {
        return try {
            val raw = context.contentResolver.openInputStream(android.net.Uri.parse(uriString))?.use {
                it.readBytes()
            } ?: return null
            if (raw.size < 64) return null

            val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

            // Downsample large covers; art is never shown larger than ~512px.
            val opts = android.graphics.BitmapFactory.Options().apply {
                var scale = 1
                while (bounds.outWidth / (scale * 2) >= 512) scale *= 2
                inSampleSize = scale
            }
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(raw, 0, raw.size, opts)
                ?: return null
            val out = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, out)
            bitmap.recycle()
            out.toByteArray()
        } catch (e: Exception) {
            null
        } catch (e: OutOfMemoryError) {
            null
        }
    }

    private fun generateVideoThumbnail(path: String, outputPath: String, maxWidth: Int): String? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            // 1s in usually avoids a black/blank opening frame, but videos
            // shorter than that (or with metadata reporting 0 duration) had
            // no frame at 1s and silently returned no thumbnail at all —
            // fall back to the very first frame in that case.
            fun frameAt(timeUs: Long) = if (android.os.Build.VERSION.SDK_INT >= 29) {
                retriever.getScaledFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, maxWidth, maxWidth)
            } else {
                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            }
            val bitmap = frameAt(1_000_000L) ?: frameAt(0L) ?: return null

            File(outputPath).parentFile?.mkdirs()
            FileOutputStream(outputPath).use { out ->
                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out)
            }
            outputPath
        } catch (e: Exception) {
            null
        } finally {
            retriever.release()
        }
    }
}
