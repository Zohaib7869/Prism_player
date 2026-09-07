# ExoPlayer / media3 / audio_service
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media.** { *; }
-keep class androidx.media3.** { *; }
# Keep native plugin classes (platform channel method names accessed via reflection-free MethodChannel, safe to keep anyway)
-keep class com.prismplayer.app.** { *; }

# local_auth / BiometricPrompt needs AndroidX fragment + biometric classes intact
-keep class androidx.fragment.app.** { *; }
-keep class androidx.biometric.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn androidx.biometric.**

# media_kit / libmpv — used for remote (YouTube) playback. These classes are
# reached from JNI, so R8 can't see the references and will strip them in
# release builds, which shows up as remote video failing to start.
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.alexmercerind.mediakitandroidhelper.** { *; }
-keep class media.kit.** { *; }
-dontwarn com.alexmercerind.**
