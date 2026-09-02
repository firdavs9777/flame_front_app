import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept OUT of the repository.
//
// android/key.properties holds the upload keystore's location and passwords and
// is gitignored along with *.jks/*.keystore. Absent on CI and on any machine
// that has not been handed the keystore, which is why every read below is
// optional and the release build falls back to debug signing rather than
// failing to configure.
//
// That fallback is a convenience for `flutter run --release`, NOT a way to ship:
// the debug keystore is the SDK's shared one (password "android", alias
// "androiddebugkey"), so a debug-signed bundle is signed with a key every
// developer alive already has. Play refuses those uploads outright. The warning
// below exists because the old config did this silently, which is how a release
// build gets to the upload step before anyone notices.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseKeystore = keystorePropertiesFile.exists() &&
    keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.bananatalk.flame"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Must stay in sync with the iOS bundle ID (com.bananatalk.flame): the
        // Google, Apple and Meta consoles all tie credentials to these IDs.
        applicationId = "com.bananatalk.flame"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Fails the build for the tasks that produce something uploadable, rather than
// letting a debug-signed artifact reach the Play Console. Local `--release` runs
// and every other task are untouched.
if (!hasReleaseKeystore) {
    gradle.taskGraph.whenReady {
        val uploadable = allTasks.any {
            it.name.contains("bundleRelease") || it.name.contains("assembleRelease")
        }
        if (uploadable) {
            throw GradleException(
                "Release artifact requested with no upload keystore.\n" +
                    "android/key.properties is missing, so this build would be signed with the " +
                    "SDK's shared debug key and rejected by Play.\n" +
                    "Create the keystore, then android/key.properties with storeFile, " +
                    "storePassword, keyAlias and keyPassword. See android/key.properties.example."
            )
        }
    }
}

flutter {
    source = "../.."
}
