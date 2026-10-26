import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.net.URI
import java.security.MessageDigest

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nirmal.nivio"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Enable core library desugaring for flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nirmal.nivio"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // Enable multidex for the app
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            pickFirsts += setOf("**/libc++_shared.so")
        }
    }
}

flutter {
    source = "../.."
}

// ── mpv: mpvlibAndroid instead of media_kit's bundled libmpv ──
// media_kit ships an mpv 0.36 build with only the OpenGL renderer. mpvlibAndroid
// (MIT wrapper; mpv/FFmpeg are LGPL, loaded as shared libraries) adds Vulkan,
// libplacebo and the gpu-next renderer, which HDR output and better tone
// mapping need. libmpv.so has the same name as media_kit's, and the app
// module's jniLibs take priority, so it replaces it (its FFmpeg is renamed, below).
// Downloaded once into build/ and checked against the release's SHA-256.
val mpvlibVersion = "1.1.4"
val mpvlibSha256 = "bebfa2ad542d4d2ca1fe16f1173ea59671d48f8c35fa033ff8c39a31e7f11bd5"
val mpvlibDir = layout.buildDirectory.dir("mpvlib")

val fetchMpvlib by tasks.registering {
    val outDir = mpvlibDir
    outputs.dir(outDir)
    doLast {
        val dir = outDir.get().asFile
        val aar = File(dir, "mpvlib-$mpvlibVersion.aar")
        fun sha256(f: File): String {
            val md = MessageDigest.getInstance("SHA-256")
            val input: InputStream = FileInputStream(f)
            try {
                val buf = ByteArray(1 shl 16)
                while (true) {
                    val n: Int = input.read(buf)
                    if (n < 0) break
                    md.update(buf, 0, n)
                }
            } finally {
                input.close()
            }
            val sb = StringBuilder()
            for (b: Byte in md.digest()) sb.append(String.format("%02x", b.toInt() and 0xff))
            return sb.toString()
        }
        if (!aar.exists() || sha256(aar) != mpvlibSha256) {
            dir.mkdirs()
            val url = "https://github.com/nirmaleeswar30/mpvlibAndroid/releases/download/v1.1.4-dv/mpvlib-$mpvlibVersion.aar"
            println("Downloading $url")
            val input: InputStream = URI(url).toURL().openStream()
            val output = FileOutputStream(aar)
            try {
                input.copyTo(output)
            } finally {
                input.close()
                output.close()
            }
            check(sha256(aar) == mpvlibSha256) { "mpvlib-$mpvlibVersion.aar checksum mismatch" }
        }
        val jniDir = File(dir, "jni")
        jniDir.deleteRecursively()
        File(dir, "assets").deleteRecursively()
        project.copy {
            from(zipTree(aar))
            // libplayer.so is mpv-android's Java glue; media_kit talks to libmpv directly.
            include("jni/**")
            // CA bundle for mpv's HTTPS (libcurl verifies certificates); copied to
            // the files dir at startup, see lib/core/mpv_android_setup.dart.
            include("assets/cacert.pem")
            exclude("**/libplayer.so")
            into(dir)
        }

        // FFmpegKit (downloads) ships its own, different FFmpeg under the same
        // file names (libavcodec.so, …). Give mpv's copies their own names so
        // both load side by side: rename the files and patch every reference
        // (DT_NEEDED / SONAME) in place. New names are the same length, so the
        // ELF string tables keep their layout.
        val renames = linkedMapOf(
            "libavcodec.so" to "libmvcodec.so",
            "libavdevice.so" to "libmvdevice.so",
            "libavfilter.so" to "libmvfilter.so",
            "libavformat.so" to "libmvformat.so",
            "libavutil.so" to "libmvutil.so",
            "libswresample.so" to "libmwresample.so",
            "libswscale.so" to "libmwscale.so",
        )
        fun replaceAll(data: ByteArray, from: ByteArray, to: ByteArray): Int {
            var count = 0
            var i = 0
            while (i <= data.size - from.size) {
                var match = true
                for (j in from.indices) {
                    if (data[i + j] != from[j]) {
                        match = false
                        break
                    }
                }
                if (match) {
                    for (j in to.indices) data[i + j] = to[j]
                    count++
                    i += from.size
                } else {
                    i++
                }
            }
            return count
        }
        jniDir.listFiles()?.filter { it.isDirectory }?.forEach { abiDir ->
            abiDir.listFiles()?.filter { it.name.endsWith(".so") && it.name != "libc++_shared.so" }?.forEach { so ->
                val bytes = so.readBytes()
                var patched = 0
                for ((from, to) in renames) {
                    // Match "libavcodec.so" followed by NUL, i.e. the exact string-table entry.
                    patched += replaceAll(bytes, (from + "\u0000").toByteArray(), (to + "\u0000").toByteArray())
                }
                if (patched > 0) so.writeBytes(bytes)
            }
            for ((from, to) in renames) {
                val f = File(abiDir, from)
                if (f.exists()) check(f.renameTo(File(abiDir, to))) { "Could not rename $f" }
            }
        }
    }
}

android.sourceSets.getByName("main").jniLibs.srcDir(mpvlibDir.map { it.dir("jni") })
android.sourceSets.getByName("main").assets.srcDir(mpvlibDir.map { it.dir("assets") })
tasks.named("preBuild") { dependsOn(fetchMpvlib) }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
