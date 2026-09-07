package com.prismplayer.app

import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Single native entry point. Registers Prism Player's custom platform channels.
 * Audio background playback / media notifications are handled by the audio_service
 * plugin's own service (declared in AndroidManifest.xml).
 *
 * IMPORTANT: MainActivity must extend AudioServiceFragmentActivity, NOT
 * AudioServiceActivity. AudioServiceActivity extends FlutterActivity (not a
 * FragmentActivity), so androidx BiometricPrompt — used by local_auth for the
 * Safe Media fingerprint/face unlock — cannot attach and local_auth fails with
 * `no_fragment_activity` ("This screen can't show the biometric prompt right
 * now"). AudioServiceFragmentActivity extends FlutterFragmentActivity and keeps
 * the audio_service media-session wiring intact.
 */
class MainActivity : AudioServiceFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        AudioEffectsPlugin(context = this).registerWith(flutterEngine)
        AudioVisualizerPlugin(context = this).registerWith(flutterEngine)
        AudioExtractionPlugin(context = this).registerWith(flutterEngine)
        MediaMuxPlugin(context = this).registerWith(flutterEngine)
        MediaScannerPlugin(context = this).registerWith(flutterEngine)
        SafeStorageBridgePlugin(context = this).registerWith(flutterEngine)
        StorageScanPlugin(context = this).registerWith(flutterEngine)
        // Spike 1 only: is_available / get_version. See YoutubeYtDlpPlugin kdoc.
        YoutubeYtDlpPlugin(context = this).registerWith(flutterEngine)
    }
}
