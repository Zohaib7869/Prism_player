package com.prismplayer.app

import android.content.Context
import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.Virtualizer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Wraps Android's native AudioEffects (Equalizer, BassBoost, Virtualizer, LoudnessEnhancer)
 * and attaches them to the audio session ID of whichever player (just_audio / video_player)
 * is currently active. A single LoudnessEnhancer instance is shared between the "preamp"
 * used by the Equalizer screen and the standalone Volume Booster, since Android only expects
 * one active LoudnessEnhancer per audio session.
 *
 * Channel: com.prismplayer.app/audio_effects
 */
class AudioEffectsPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private val channelName = "com.prismplayer.app/audio_effects"
    private var methodChannel: MethodChannel? = null

    private var equalizer: Equalizer? = null
    private var bassBoost: BassBoost? = null
    private var virtualizer: Virtualizer? = null
    private var loudnessEnhancer: LoudnessEnhancer? = null
    private var currentSessionId: Int = -1

    // LoudnessEnhancer target gain range we allow, in millibels. 2000 mB == +20 dB.
    // We cap boost well below the hardware clipping point most devices hit.
    private val maxVolumeBoostMillibels = 2000

    fun registerWith(flutterEngine: FlutterEngine) {
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler(this)
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
                "getEqualizerInfo" -> result.success(getEqualizerInfo())
                "setEqualizerEnabled" -> {
                    equalizer?.enabled = call.argument<Boolean>("enabled") ?: true
                    result.success(true)
                }
                "setBandLevel" -> {
                    val band = (call.argument<Int>("band") ?: 0).toShort()
                    val level = (call.argument<Int>("levelMb") ?: 0)
                    // The app's preset curves and slider assume a fixed 10-band
                    // -1500..1500 layout, but the real hardware/software
                    // Equalizer on a given device can expose fewer bands and/or
                    // a narrower level range. Calling setBandLevel outside
                    // either bound throws "AudioEffect: bad parameter value"
                    // (visible as a stream of non-fatal EqualizerService
                    // errors) and skips every band after the first bad one.
                    // Clamp defensively instead of trusting the caller.
                    val eq = equalizer
                    if (eq != null && band < eq.numberOfBands) {
                        val range = eq.bandLevelRange
                        val clamped = level.coerceIn(range[0].toInt(), range[1].toInt()).toShort()
                        try {
                            eq.setBandLevel(band, clamped)
                        } catch (e: Exception) {
                            // Unsupported band/level combo on this device — non-fatal.
                        }
                    }
                    result.success(true)
                }
                "getPresetNames" -> {
                    val eq = equalizer
                    val names = mutableListOf<String>()
                    if (eq != null) {
                        for (i in 0 until eq.numberOfPresets) {
                            names.add(eq.getPresetName(i.toShort()))
                        }
                    }
                    result.success(names)
                }
                "usePreset" -> {
                    val index = (call.argument<Int>("index") ?: 0).toShort()
                    val eq = equalizer
                    if (eq != null && index >= 0 && index < eq.numberOfPresets) {
                        try {
                            eq.usePreset(index)
                        } catch (e: Exception) {
                            // Unsupported preset on this device — non-fatal.
                        }
                    }
                    result.success(true)
                }
                "setBassBoostEnabled" -> {
                    bassBoost?.enabled = call.argument<Boolean>("enabled") ?: true
                    result.success(true)
                }
                "setBassBoostStrength" -> {
                    val strengthInt = (call.argument<Int>("strength") ?: 0).coerceIn(0, 1000)
                    // Not every device's BassBoost implementation supports strength
                    // control (getStrengthSupported() == false on several OEM skins /
                    // emulators) — calling setStrength there throws and used to abort
                    // this whole method call, so the enabled-flag change made just
                    // before it would look like it "did nothing" from the Dart side.
                    if (bassBoost?.strengthSupported == true) {
                        try {
                            bassBoost?.setStrength(strengthInt.toShort())
                        } catch (e: Exception) {
                            // Unsupported on this device — enabled/on-off still works.
                        }
                    }
                    result.success(true)
                }
                "setVirtualizerEnabled" -> {
                    virtualizer?.enabled = call.argument<Boolean>("enabled") ?: true
                    result.success(true)
                }
                "setVirtualizerStrength" -> {
                    val strengthInt = (call.argument<Int>("strength") ?: 0).coerceIn(0, 1000)
                    if (virtualizer?.strengthSupported == true) {
                        try {
                            virtualizer?.setStrength(strengthInt.toShort())
                        } catch (e: Exception) {
                            // Unsupported on this device — enabled/on-off still works.
                        }
                    }
                    result.success(true)
                }
                "setVolumeBoostPercent" -> {
                    // percent: 100 (normal) .. 200 (double). Maps linearly to millibel gain.
                    val percent = (call.argument<Int>("percent") ?: 100).coerceIn(100, 200)
                    val fraction = (percent - 100) / 100.0
                    val gainMb = (fraction * maxVolumeBoostMillibels).toInt()
                    loudnessEnhancer?.let {
                        it.setTargetGain(gainMb)
                        it.enabled = gainMb > 0
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("AUDIO_EFFECTS_ERROR", e.message, null)
        }
    }

    private fun attach(sessionId: Int) {
        if (sessionId == currentSessionId && equalizer != null) return
        release()
        currentSessionId = sessionId
        if (sessionId == -1 || sessionId == 0) return

        // Each effect is constructed independently: some devices don't support
        // every effect type (e.g. no hardware Virtualizer), and letting one
        // constructor throw used to abort this whole function, leaving
        // bassBoost/virtualizer/loudnessEnhancer all null even though only one
        // of them was actually unsupported. That silently broke every other
        // effect (including the plain band Equalizer) whenever it happened.
        try {
            equalizer = Equalizer(0, sessionId).apply { enabled = true }
        } catch (e: Exception) {
            equalizer = null
        }
        try {
            bassBoost = BassBoost(0, sessionId).apply { enabled = false }
        } catch (e: Exception) {
            bassBoost = null
        }
        try {
            virtualizer = Virtualizer(0, sessionId).apply { enabled = false }
        } catch (e: Exception) {
            virtualizer = null
        }
        try {
            loudnessEnhancer = LoudnessEnhancer(sessionId).apply {
                setTargetGain(0)
                enabled = false
            }
        } catch (e: Exception) {
            loudnessEnhancer = null
        }
    }

    private fun detach() {
        release()
    }

    private fun release() {
        equalizer?.release()
        bassBoost?.release()
        virtualizer?.release()
        loudnessEnhancer?.release()
        equalizer = null
        bassBoost = null
        virtualizer = null
        loudnessEnhancer = null
        currentSessionId = -1
    }

    private fun getEqualizerInfo(): Map<String, Any> {
        val eq = equalizer ?: return mapOf(
            "numberOfBands" to 0,
            "minLevelMb" to 0,
            "maxLevelMb" to 0,
            "centerFrequenciesHz" to emptyList<Int>()
        )
        val range = eq.bandLevelRange
        val bands = (0 until eq.numberOfBands).map { eq.getCenterFreq(it.toShort()) / 1000 }
        return mapOf(
            "numberOfBands" to eq.numberOfBands.toInt(),
            "minLevelMb" to range[0].toInt(),
            "maxLevelMb" to range[1].toInt(),
            "centerFrequenciesHz" to bands
        )
    }
}
