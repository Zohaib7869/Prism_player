package com.prismplayer.app

import android.content.Context
import android.media.audiofx.Visualizer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

/**
 * Real-time audio visualizer backed by Android's native `Visualizer` audio
 * effect, attached to the same audio session id used for the Equalizer (see
 * AudioEffectsPlugin). It captures live FFT magnitude data straight off
 * whatever is actually playing through that session and streams it to Dart
 * as a fixed-size array of normalized (0..1) bar magnitudes — this is real
 * spectrum data reacting to the audio in real time, not a canned animation.
 *
 * Like AudioEffectsPlugin, this only works for audio sessions exposed by
 * just_audio (Music/Audio playback, "Play as Audio"): video_player does not
 * expose an Android audio session id, so there is nothing to attach to
 * during native video playback.
 *
 * Method channel: com.prismplayer.app/audio_visualizer  (attach / detach)
 * Event channel:  com.prismplayer.app/audio_visualizer/events  (bar data stream)
 */
class AudioVisualizerPlugin(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val methodChannelName = "com.prismplayer.app/audio_visualizer"
    private val eventChannelName = "com.prismplayer.app/audio_visualizer/events"

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var visualizer: Visualizer? = null
    private var currentSessionId: Int = -1

    // Number of bars sent to Dart per frame. The painters on the Dart side
    // resample this to however many bars a given visualizer style draws.
    private val barCount = 32

    // --- Auto-gain + envelope state -----------------------------------
    // A fixed divisor to normalize raw FFT magnitude never looks right
    // across different songs/volumes: quiet tracks stay pinned near the
    // floor, loud ones pin every bar near the ceiling, and either way the
    // bars barely seem to move. Instead we track a decaying "recent peak"
    // per bar and normalize against *that*, so every bar always uses close
    // to its full 0..1 range regardless of how loud the current track or
    // device volume is — this is the standard auto-gain-control technique
    // real spectrum visualizers use.
    private val runningPeak = DoubleArray(barCount) { 8.0 }
    // Smoothed (displayed) value per bar. Rises quickly (fast attack) so
    // beats feel instant, falls more slowly (slower release) so bars don't
    // flicker frame-to-frame — this is what actually reads as "dancing"
    // instead of jittering.
    private val smoothedBars = DoubleArray(barCount)

    fun registerWith(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
        methodChannel?.setMethodCallHandler(this)
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
        eventChannel?.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "attach" -> {
                    val sessionId = call.argument<Int>("sessionId") ?: -1
                    attach(sessionId)
                    result.success(true)
                }
                "detach" -> {
                    detach()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("AUDIO_VISUALIZER_ERROR", e.message, null)
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun attach(sessionId: Int) {
        if (sessionId == currentSessionId && visualizer != null) return
        release()
        currentSessionId = sessionId
        if (sessionId == -1 || sessionId == 0) return

        // Fresh track / fresh session — don't let it inherit the previous
        // track's auto-gain peak or smoothed values (would otherwise look
        // muted or over-amplified for the first second or two).
        runningPeak.fill(8.0)
        smoothedBars.fill(0.0)

        try {
            val captureSize = Visualizer.getCaptureSizeRange()[1]
            val v = Visualizer(sessionId)
            v.captureSize = captureSize
            // Cap the capture rate: getMaxCaptureRate() can be very high on
            // some devices and there is no benefit pushing more frames than
            // the UI can usefully draw — 20-ish Hz is smooth and cheap.
            val rate = min(Visualizer.getMaxCaptureRate(), 20000)
            v.setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                override fun onWaveFormDataCapture(visualizer: Visualizer?, waveform: ByteArray?, samplingRate: Int) {
                    // Not used — FFT capture below drives the spectrum bars.
                }

                override fun onFftDataCapture(visualizer: Visualizer?, fft: ByteArray?, samplingRate: Int) {
                    if (fft == null || fft.isEmpty()) return
                    emitBars(fft)
                }
            }, rate, false, true)
            v.enabled = true
            visualizer = v
        } catch (e: Exception) {
            // Some devices/OEM builds disallow the Visualizer effect entirely
            // (or it's already claimed elsewhere) — fail silently; the Dart
            // side falls back to its simulated animation when no data arrives.
            visualizer = null
        }
    }

    private fun detach() {
        release()
    }

    private fun release() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (e: Exception) {
            // Ignore — already released or in a bad state.
        }
        visualizer = null
        currentSessionId = -1
    }

    /**
     * Converts a raw FFT capture (format: byte[0]=DC magnitude, byte[1]=Nyquist
     * magnitude, then alternating (re, im) pairs for the bins in between) into
     * [barCount] normalized 0..1 magnitudes — auto-gained and attack/decay
     * smoothed per bar — and pushes them to Dart.
     */
    private fun emitBars(fft: ByteArray) {
        val bins = fft.size / 2
        if (bins <= 1) return
        val binsPerBar = maxOf(1, (bins - 1) / barCount)

        for (i in 0 until barCount) {
            var sum = 0.0
            var count = 0
            val start = 1 + i * binsPerBar
            val end = minOf(bins, start + binsPerBar)
            for (j in start until end) {
                val idx = j * 2
                if (idx + 1 >= fft.size) break
                val re = fft[idx].toInt()
                val im = fft[idx + 1].toInt()
                sum += sqrt((re * re + im * im).toDouble())
                count++
            }
            val rawMagnitude = if (count > 0) sum / count else 0.0

            // Auto-gain: this bar's own recent peak decays slowly over time,
            // but jumps up instantly the moment a louder hit comes through —
            // so the *visible* range always stretches to fit whatever this
            // bar has actually been doing lately, on any song, at any volume.
            runningPeak[i] = max(rawMagnitude, runningPeak[i] * 0.985)
            val peak = max(runningPeak[i], 6.0) // floor avoids amplifying near-silence into noise
            val normalized = (rawMagnitude / peak).coerceIn(0.0, 1.0)
            // Gentle curve (pow < 1) lifts mid-quiet moments so they still
            // read as visible movement instead of hugging the bottom.
            val shaped = normalized.pow(0.6)

            val current = smoothedBars[i]
            smoothedBars[i] = if (shaped > current) {
                current + (shaped - current) * 0.75 // fast attack — beat hits register immediately
            } else {
                current + (shaped - current) * 0.30 // slower release — natural fall, not a flicker
            }
        }

        eventSink?.success(smoothedBars.toList())
    }
}
