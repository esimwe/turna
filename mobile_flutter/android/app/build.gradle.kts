plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

configurations.configureEach {
    resolutionStrategy.dependencySubstitution {
        substitute(module("com.github.davidliu:audioswitch"))
            .using(module("com.twilio:audioswitch:1.2.4"))
            .because(
                "flutter_webrtc still points at the old JitPack coordinate; use the official Maven Central artifact instead.",
            )
    }
}

android {
    namespace = "com.turna.chat"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.turna.chat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("me.leolin:ShortcutBadger:1.1.22@aar")
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    implementation("androidx.media3:media3-transformer:1.5.1")
    implementation("androidx.media3:media3-effect:1.5.1")
}
