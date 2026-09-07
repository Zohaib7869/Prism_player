package com.prismplayer.app

import android.util.Log
import dev.ffmpegkit_maintained.ytdlp.YtDlp
import dev.ffmpegkit_maintained.ytdlp.YtDlpException
import io.flutter.app.FlutterApplication
import java.util.concurrent.Executors

/**
 * Application class for Prism Player.
 *
 * Must extend io.flutter.app.FlutterApplication (not plain Application) so existing
 * Flutter engine/plugin behaviour that previously relied on "${applicationName}" in
 * AndroidManifest.xml is preserved unchanged.
 *
 * Spike 1 scope only (see prism-player-ytdlp-migration-architecture.md §20 step 1):
 * performs a single YtDlp.init(applicationContext) off the main thread as soon as the
 * process starts, so YoutubeYtDlpPlugin has a ready/failed signal by the time Dart makes
 * its first is_available / get_version call. No extraction, no download, no other logic.
 *
 * YtDlp.init() is documented as idempotent ("if (initialized) return"), but this class
 * only ever calls it once, from a single background thread, on app startup.
 */
class PrismPlayerApplication : FlutterApplication() {

    companion object {
        private const val TAG = "PrismPlayerApplication"

        @Volatile
        var ytDlpInitialized: Boolean = false
            private set

        @Volatile
        var ytDlpInitError: String? = null
            private set

        /// yt-dlp version actually importable after the asset override,
        /// or null if the override failed and the bundled copy is in use.
        @Volatile
        var ytDlpVersion: String? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()

        // Single background thread, fire-and-forget. Not the app's shared executor pool
        // (none exists yet at this scope) — deliberately isolated so a Chaquopy/JNI/asset
        // failure here can never block Flutter engine startup or the main thread.
        Executors.newSingleThreadExecutor().execute {
            try {
                YtDlp.init(applicationContext)

                // Shadow the AAR's yt-dlp 2026.06.09 with the newer wheel in
                // assets/. Must happen after init (Python must exist) and
                // before ytDlpInitialized flips true, since every plugin method
                // is gated on that flag — so nothing can import yt_dlp first.
                // Returns null and leaves the bundled copy in place on failure.
                ytDlpVersion = YtDlpUpdater.install(applicationContext)

                ytDlpInitialized = true
                ytDlpInitError = null
                Log.i(TAG, "YtDlp.init() succeeded")
            } catch (e: YtDlpException) {
                ytDlpInitialized = false
                ytDlpInitError = e.message ?: e.toString()
                Log.e(TAG, "YtDlp.init() failed", e)
            } catch (e: Throwable) {
                // Broad catch is intentional here: this is the riskiest unknown in the
                // whole migration (Chaquopy asset merge / JNI load from a plain AAR with
                // no Chaquopy Gradle plugin). Any failure mode — UnsatisfiedLinkError,
                // asset SHA1 mismatch, etc. — must surface via is_available/get_version
                // instead of crashing the process.
                ytDlpInitialized = false
                ytDlpInitError = e.message ?: e.toString()
                Log.e(TAG, "YtDlp.init() failed with unexpected error", e)
            }
        }
    }
}
