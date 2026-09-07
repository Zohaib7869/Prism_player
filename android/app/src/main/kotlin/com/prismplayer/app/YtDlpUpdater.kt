package com.prismplayer.app

import android.content.Context
import android.util.Log
import com.chaquo.python.Python
import java.io.File
import java.util.zip.ZipInputStream

/**
 * Shadows the yt-dlp bundled inside the AAR with a newer copy shipped as an
 * app asset.
 *
 * WHY
 * ---
 * `dev.ffmpegkit-maintained:yt-dlp-android:2.0.2` bundles yt-dlp 2026.06.09.
 * Confirmed on device 2026-09-07: that version does not know the `visionos`
 * player client, so the client list falls through to tv_simply / android_vr /
 * mweb, all of which now require a GVS PO token. 2026.06.09 hands the URL over
 * anyway instead of skipping the format, and googlevideo answers HTTP 403.
 * yt-dlp 2026.8.19 on desktop downloads the same video through `visionos` in
 * about a second with no PO token at all.
 *
 * YouTube breaks extractors faster than an AAR maintainer can republish, so
 * pinning the fix to a dependency bump would put us right back here in a month.
 * This decouples the two: yt-dlp is pure Python (verified: the wheel contains
 * zero .so/.pyd files), so prepending an extracted wheel to `sys.path` shadows
 * the bundled package entirely. Updating yt-dlp then means dropping a newer
 * .whl into assets and bumping [BUNDLED_VERSION] — no native rebuild, no
 * Chaquopy Gradle plugin, no waiting on anyone.
 *
 * LICENSE
 * -------
 * yt-dlp is released under the Unlicense (public domain). Redistributing it
 * inside this APK is permitted. The wheel ships its own LICENSE file, which the
 * extraction below preserves.
 *
 * ORDERING
 * --------
 * [install] must run after `YtDlp.init()` (Python has to exist) but before any
 * `import yt_dlp`. PrismPlayerApplication calls it between init succeeding and
 * `ytDlpInitialized` being set true, and every plugin method is gated on that
 * flag, so no extraction can race it.
 */
object YtDlpUpdater {

    private const val TAG = "YtDlpUpdater"
    private const val ASSET_PATH = "ytdlp/yt_dlp.whl"

    /** Bump together with the asset. Also names the install directory. */
    const val BUNDLED_VERSION = "2026.08.19"

    /**
     * Extracts the bundled wheel (first run only) and prepends it to sys.path.
     *
     * @return the yt-dlp version actually importable afterwards, or null if the
     *   override could not be applied — in which case the AAR's own copy stays
     *   in use and the app degrades to previous behaviour rather than failing.
     */
    fun install(context: Context): String? {
        return try {
            val dir = File(context.filesDir, "ytdlp-$BUNDLED_VERSION")
            val marker = File(dir, ".installed")

            if (marker.exists()) {
                Log.i(TAG, "[YT] override already extracted at ${dir.absolutePath}")
            } else {
                // A previous partial extraction, or an older version's directory,
                // must not be reused — start clean.
                if (dir.exists()) dir.deleteRecursively()
                dir.mkdirs()
                val bytes = extractWheel(context, dir)
                marker.writeText(BUNDLED_VERSION)
                Log.i(TAG, "[YT] extracted yt-dlp $BUNDLED_VERSION ($bytes bytes)")
            }

            prependToPath(dir.absolutePath)

            val version = importedVersion()
            if (version == null) {
                Log.w(TAG, "[YT] override applied but version unreadable")
            } else if (version != BUNDLED_VERSION) {
                // Not fatal: the import may legitimately resolve differently.
                // Log loudly, because it means the override did not take.
                Log.w(TAG, "[YT] expected $BUNDLED_VERSION, got $version — override did NOT take")
            } else {
                Log.i(TAG, "[YT] yt-dlp override active: $version")
            }
            version
        } catch (e: Throwable) {
            // Never fatal. If this fails the AAR's bundled yt-dlp is still there.
            Log.e(TAG, "[YT] yt-dlp override failed, falling back to bundled copy", e)
            null
        }
    }

    /** Unpacks the wheel (an ordinary zip) into [dir]. Returns bytes written. */
    private fun extractWheel(context: Context, dir: File): Long {
        var total = 0L
        val canonicalRoot = dir.canonicalPath + File.separator

        context.assets.open(ASSET_PATH).use { asset ->
            ZipInputStream(asset.buffered()).use { zis ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val entry = zis.nextEntry ?: break
                    val target = File(dir, entry.name)

                    // Zip-slip guard: an entry named "../../x" would otherwise
                    // write outside filesDir.
                    if (!target.canonicalPath.startsWith(canonicalRoot)) {
                        throw SecurityException("wheel entry escapes target dir: ${entry.name}")
                    }

                    if (entry.isDirectory) {
                        target.mkdirs()
                    } else {
                        target.parentFile?.mkdirs()
                        target.outputStream().buffered().use { out ->
                            while (true) {
                                val n = zis.read(buffer)
                                if (n <= 0) break
                                out.write(buffer, 0, n)
                                total += n
                            }
                        }
                    }
                    zis.closeEntry()
                }
            }
        }
        return total
    }

    /**
     * Puts [path] at the front of sys.path and drops any already-imported
     * yt_dlp modules, so a later `import yt_dlp` resolves to the new copy
     * rather than a cached reference to the bundled one.
     */
    private fun prependToPath(path: String) {
        val py = Python.getInstance()
        val sys = py.getModule("sys")

        val sysPath = sys["path"] ?: throw IllegalStateException("sys.path unavailable")
        // Remove first in case install() somehow runs twice — a duplicated
        // entry is harmless but makes the log confusing.
        try {
            sysPath.callAttr("remove", path)
        } catch (_: Throwable) {
            // Not present; expected on the normal first call.
        }
        sysPath.callAttr("insert", 0, path)

        // Purge cached yt_dlp modules. On a cold start there are none, but the
        // diagnostics path in main.dart can import early in debug builds.
        val modules = sys["modules"]
        if (modules != null) {
            val stale = py.getBuiltins().callAttr("list", modules.callAttr("keys"))
                .asList()
                .map { it.toString() }
                .filter { it == "yt_dlp" || it.startsWith("yt_dlp.") }
            for (name in stale) {
                try {
                    modules.callAttr("pop", name, null)
                } catch (e: Throwable) {
                    Log.w(TAG, "[YT] could not evict $name: ${e.message}")
                }
            }
            if (stale.isNotEmpty()) {
                Log.i(TAG, "[YT] evicted ${stale.size} cached yt_dlp modules")
            }
        }

        // importlib caches directory listings; a freshly created dir needs this
        // or the import can miss it.
        try {
            py.getModule("importlib").callAttr("invalidate_caches")
        } catch (e: Throwable) {
            Log.w(TAG, "[YT] invalidate_caches failed: ${e.message}")
        }
    }

    private fun importedVersion(): String? = try {
        Python.getInstance().getModule("yt_dlp.version").get("__version__")?.toString()
    } catch (e: Throwable) {
        Log.w(TAG, "[YT] could not read yt_dlp.version: ${e.message}")
        null
    }
}
