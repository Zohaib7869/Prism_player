package com.prismplayer.app

import android.content.Context
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Extracts the audio track from a video file into a standalone .m4a file using
 * MediaExtractor + MediaMuxer. This performs a genuine stream copy of the compressed
 * audio track (no re-encoding), which works whenever the source audio is AAC — the
 * overwhelmingly common case for MP4/MKV/MOV/3GP/TS files. Non-AAC audio tracks
 * (e.g. raw PCM, Vorbis inside WebM) will fail muxing into the MPEG4 container and are
 * reported back as a clear error rather than silently producing a broken/fake file.
 * A full transcode pipeline (decode -> re-encode to AAC/MP3) is a heavier addition that
 * is not included in this pass; see README for details.
 *
 * Method channel: com.prismplayer.app/audio_extraction  (start/cancel)
 * Event channel:  com.prismplayer.app/audio_extraction_progress (progress/completion/error)
 */
class AudioExtractionPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannelName = "com.prismplayer.app/audio_extraction"
    private val eventChannelName = "com.prismplayer.app/audio_extraction_progress"

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var cancelled = false

    fun registerWith(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "extractAudio" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                if (sourcePath == null || outputPath == null) {
                    result.error("BAD_ARGS", "sourcePath and outputPath are required", null)
                    return
                }
                cancelled = false
                result.success(true) // extraction runs async; progress/completion via event channel
                executor.execute { runExtraction(sourcePath, outputPath) }
            }
            "cancelExtraction" -> {
                cancelled = true
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun runExtraction(sourcePath: String, outputPath: String) {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            extractor.setDataSource(sourcePath)

            var audioTrackIndex = -1
            var audioFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    audioFormat = format
                    break
                }
            }

            if (audioTrackIndex == -1 || audioFormat == null) {
                emit(mapOf("status" to "error", "message" to "No audio track found in source file"))
                return
            }

            val mime = audioFormat.getString(MediaFormat.KEY_MIME) ?: ""
            if (!mime.contains("aac") && !mime.contains("mp4a")) {
                emit(
                    mapOf(
                        "status" to "error",
                        "message" to
                            "Audio codec ($mime) can't be copied into an M4A container without " +
                            "re-encoding, which isn't supported in this build."
                    )
                )
                return
            }

            File(outputPath).parentFile?.mkdirs()
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val muxerTrackIndex = muxer.addTrack(audioFormat)
            muxer.start()

            extractor.selectTrack(audioTrackIndex)

            val durationUs = try {
                audioFormat.getLong(MediaFormat.KEY_DURATION)
            } catch (e: Exception) {
                1L
            }.coerceAtLeast(1L)
            val bufferSize = 1 shl 20 // 1 MB
            val buffer = ByteBuffer.allocate(bufferSize)
            val bufferInfo = android.media.MediaCodec.BufferInfo()

            var lastEmitPercent = -1
            while (!cancelled) {
                buffer.clear()
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break

                bufferInfo.offset = 0
                bufferInfo.size = sampleSize
                bufferInfo.presentationTimeUs = extractor.sampleTime
                bufferInfo.flags = extractor.sampleFlags

                muxer.writeSampleData(muxerTrackIndex, buffer, bufferInfo)
                extractor.advance()

                val percent = ((bufferInfo.presentationTimeUs * 100) / durationUs).toInt().coerceIn(0, 100)
                if (percent != lastEmitPercent) {
                    lastEmitPercent = percent
                    emit(mapOf("status" to "progress", "progress" to percent))
                }
            }

            if (cancelled) {
                emit(mapOf("status" to "cancelled"))
                File(outputPath).delete()
            } else {
                emit(mapOf("status" to "done", "outputPath" to outputPath))
            }
        } catch (e: Exception) {
            emit(mapOf("status" to "error", "message" to (e.message ?: "Unknown extraction error")))
            File(outputPath).delete()
        } finally {
            try {
                muxer?.stop()
                muxer?.release()
            } catch (_: Exception) {
                // muxer.stop() throws if no samples were written; safe to ignore here.
            }
            extractor.release()
        }
    }
}
