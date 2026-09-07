plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// yt-dlp-android (dev.ffmpegkit-maintained) — single upgrade point (spec item 61).
// Verified: MIT, Maven Central, self-contained AAR (Chaquopy 17.0.0 / CPython 3.13,
// yt-dlp 2026.6.9 bundled), zero transitive deps, arm64-v8a + x86_64 only, requires
// minSdk 24. See prism-player-ytdlp-migration-architecture.md for full verification.
val ytDlpAndroidVersion = "2.0.2"

android {
    namespace = "com.prismplayer.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.prismplayer.app"
        // Pinned explicitly: yt-dlp-android 2.0.2 requires API 24. Was
        // flutter.minSdkVersion — pin so a future Flutter SDK bump can't silently
        // drop below the library floor.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true

        // yt-dlp-android 2.0.2 publishes native libs for arm64-v8a and x86_64 only
        // (no armeabi-v7a, no x86). This drops 32-bit ARM device support app-wide —
        // open item #1 in the architecture doc, not yet confirmed by product owner.
        //
        // Skipped under --split-per-abi. That flag makes Flutter set AGP's own
        // `splits.abi` filters, and AGP refuses to have both that and
        // `ndk.abiFilters` configured — it fails with "Conflicting
        // configuration ... cannot be present when splits abi filters are set"
        // before it ever compares the two lists. When splitting, restrict the
        // ABIs on the command line instead:
        //
        //   flutter build apk --release --split-per-abi \
        //       --target-platform android-arm64,android-x64
        if (project.findProperty("split-per-abi") != "true") {
            ndk {
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
    }

    buildTypes {
        release {
            // Signed with a placeholder debug config so `flutter build apk --release` runs;
            // replace with a real signing config before publishing.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.media:media:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    // Chaquopy + yt-dlp bundled inside; zero transitive deps. No Chaquopy Gradle
    // plugin applied — the AAR's libs/chaquopy_java-17.0.0.jar is put on the
    // classpath by AGP directly.
    implementation("dev.ffmpegkit-maintained:yt-dlp-android:$ytDlpAndroidVersion")
}
