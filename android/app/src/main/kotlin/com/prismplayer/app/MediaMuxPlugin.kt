package com.prismplayer.app

import android.content.Context
import android.media.MediaCodec
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
import kotlin.math.max

/**
 * Merges a downloaded video-only file and audio-only file into a single MP4.
 *
 * YouTube stops offering combined (muxed) streams above 360p — every higher
 * resolution is a video-only track that has to be paired with a separate
 * audio-only track. This does that pairing with MediaExtractor + MediaMuxer,
 * which is a genuine stream copy: the compressed samples are moved into a new
 * container byte-for-byte, with no decode/re-encode step. A 1080p hour-long
 * video merges in seconds and loses nothing in quality.
 *
 * The tradeoff is that MediaMuxer's MP4 output only accepts what MP4 can hold —
 * H.264/H.265 video and AAC audio. That is why the download picker only ever
 * offers mp4-container streams: VP9/Opus (webm) would need a real transcode,
 * which would be minutes of CPU instead of seconds of I/O.
 *
 * Method channel: com.prismplayer.app/media_mux           (mux / cancelMux)
 * Event channel:  com.prismplayer.app/media_mux_progress  (progress/done/error)
 */
class MediaMuxPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannelName = "com.prismplayer.app/media_mux"
    private val eventChannelName = "com.prismplayer.app/media_mux_progress"

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
            "mux" -> {
                val videoPath = call.argument<String>("videoPath")
                val audioPath = call.argument<String>("audioPath")
                val outputPath = call.argument<String>("outputPath")
                if (videoPath == null || audioPath == null || outputPath == null) {
                    result.error("BAD_ARGS", "videoPath, audioPath and outputPath are required", null)
                    return
                }
                cancelled = false
                result.success(true) // runs async; completion arrives on the event channel
                executor.execute { runMux(videoPath, audioPath, outputPath) }
            }
            "extractAudio" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                if (sourcePath == null || outputPath == null) {
                    result.error("BAD_ARGS", "sourcePath and outputPath are required", null)
                    return
                }
                cancelled = false
                result.success(true) // runs async; completion arrives on the event channel
                executor.execute { runExtractAudio(sourcePath, outputPath) }
            }
            "cancelMux" -> {
                cancelled = true
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun emit(event: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun selectTrack(extractor: MediaExtractor, prefix: String): Int {
        for (i in 0 until extractor.trackCount) {
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith(prefix)) return i
        }
        return -1
    }

    /**
     * Copies just the audio track out of a progressive MP4 into a standalone
     * .m4a, by stream copy.
     *
     * YouTube publishes no progressive audio-only stream, and its adaptive
     * audio URLs are the ones being refused with 403. The muxed 360p file is
     * servable, and its AAC track is the same audio — so an audio download
     * falls back to fetching that file and dropping the video track here,
     * rather than saving a video under an ".m4a" name.
     */
    private fun runExtractAudio(sourcePath: String, outputPath: String) {
        val extractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var started = false

        try {
            extractor.setDataSource(sourcePath)

            val audioIndex = selectTrack(extractor, "audio/")
            if (audioIndex < 0) {
                emit(mapOf("status" to "error", "message" to "Downloaded file has no audio track"))
                return
            }

            val audioFormat = extractor.getTrackFormat(audioIndex)

            File(outputPath).parentFile?.mkdirs()
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outAudio = muxer.addTrack(audioFormat)
            muxer.start()
            started = true

            extractor.selectTrack(audioIndex)

            val buffer = ByteBuffer.allocate(max(readMaxInputSize(audioFormat), 256 * 1024))
            val info = MediaCodec.BufferInfo()
            val durationUs = readDuration(audioFormat).coerceAtLeast(1L)
            var lastPercent = -1

            while (!cancelled) {
                buffer.clear()
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break

                info.offset = 0
                info.size = sampleSize
                info.presentationTimeUs = extractor.sampleTime
                info.flags = extractor.sampleFlags

                muxer.writeSampleData(outAudio, buffer, info)
                extractor.advance()

                val percent = ((info.presentationTimeUs * 100) / durationUs).toInt().coerceIn(0, 100)
                if (percent != lastPercent) {
                    lastPercent = percent
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
            if (started) {
                try {
                    muxer?.stop()
                } catch (_: Exception) {
                }
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            extractor.release()
        }
    }

    private fun runMux(videoPath: String, audioPath: String, outputPath: String) {
        val videoExtractor = MediaExtractor()
        val audioExtractor = MediaExtractor()
        var muxer: MediaMuxer? = null
        var started = false

        try {
            videoExtractor.setDataSource(videoPath)
            audioExtractor.setDataSource(audioPath)

            val videoIndex = selectTrack(videoExtractor, "video/")
            val audioIndex = selectTrack(audioExtractor, "audio/")
            if (videoIndex < 0) {
                emit(mapOf("status" to "error", "message" to "Downloaded video file has no video track"))
                return
            }
            if (audioIndex < 0) {
                emit(mapOf("status" to "error", "message" to "Downloaded audio file has no audio track"))
                return
            }

            val videoFormat = videoExtractor.getTrackFormat(videoIndex)
            val audioFormat = audioExtractor.getTrackFormat(audioIndex)

            File(outputPath).parentFile?.mkdirs()
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val outVideo = muxer.addTrack(videoFormat)
            val outAudio = muxer.addTrack(audioFormat)
            muxer.start()
            started = true

            videoExtractor.selectTrack(videoIndex)
            audioExtractor.selectTrack(audioIndex)

            // A 1080p keyframe can be well over a megabyte; trust the format's
            // own hint when it has one rather than guessing low and throwing
            // BufferOverflowException part way through a long video.
            val bufferSize = max(
                readMaxInputSize(videoFormat),
                readMaxInputSize(audioFormat)
            )
            val buffer = ByteBuffer.allocate(bufferSize)
            val info = MediaCodec.BufferInfo()

            val durationUs = max(readDuration(videoFormat), readDuration(audioFormat)).coerceAtLeast(1L)
            var lastPercent = -1

            var videoDone = false
            var audioDone = false

            // Interleave by timestamp instead of writing one whole track then
            // the other: it keeps MediaMuxer's internal buffering small and
            // produces a file that starts playing before it is fully buffered.
            while (!cancelled && (!videoDone || !audioDone)) {
                val videoTime = if (videoDone) Long.MAX_VALUE else videoExtractor.sampleTime
                val audioTime = if (audioDone) Long.MAX_VALUE else audioExtractor.sampleTime

                if (videoTime < 0 && !videoDone) {
                    videoDone = true
                    continue
                }
                if (audioTime < 0 && !audioDone) {
                    audioDone = true
                    continue
                }
                if (videoDone && audioDone) break

                val useVideo = videoTime <= audioTime
                val extractor = if (useVideo) videoExtractor else audioExtractor
                val track = if (useVideo) outVideo else outAudio

                buffer.clear()
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) {
                    if (useVideo) videoDone = true else audioDone = true
                    continue
                }

                info.offset = 0
                info.size = sampleSize
                info.presentationTimeUs = extractor.sampleTime
                info.flags = extractor.sampleFlags

                muxer.writeSampleData(track, buffer, info)
                extractor.advance()

                val percent = ((info.presentationTimeUs * 100) / durationUs).toInt().coerceIn(0, 100)
                if (percent != lastPercent) {
                    lastPercent = percent
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
            emit(mapOf("status" to "error", "message" to (e.message ?: "Unknown muxing error")))
            File(outputPath).delete()
        } finally {
            if (started) {
                try {
                    muxer?.stop()
                } catch (_: Exception) {
                    // stop() throws if nothing was written; the error was already reported.
                }
            }
            try {
                muxer?.release()
            } catch (_: Exception) {
            }
            videoExtractor.release()
            audioExtractor.release()
        }
    }

    private fun readMaxInputSize(format: MediaFormat): Int = try {
        format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE).coerceAtLeast(256 * 1024)
    } catch (e: Exception) {
        2 * 1024 * 1024
    }

    private fun readDuration(format: MediaFormat): Long = try {
        format.getLong(MediaFormat.KEY_DURATION)
    } catch (e: Exception) {
        0L
    }
}
