import java.util.Properties
import org.gradle.api.initialization.resolve.RepositoriesMode

val flutterSdkPath =
    run {
        val properties = Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val configuredFlutterSdkPath = properties.getProperty("flutter.sdk")
        require(configuredFlutterSdkPath != null) {
            "flutter.sdk not set in local.properties"
        }
        configuredFlutterSdkPath
    }

val flutterStorageBaseUrl = System.getenv("FLUTTER_STORAGE_BASE_URL")
    ?: "https://storage.googleapis.com"

val flutterEngineRealm =
    run {
        val engineRealmFile = file("$flutterSdkPath/bin/cache/engine.realm")
        val engineRealm = if (engineRealmFile.exists()) {
            engineRealmFile.readText().trim()
        } else {
            ""
        }
        if (engineRealm.isEmpty()) "" else "$engineRealm/"
    }

pluginManagement {
    val properties = java.util.Properties()
    file("local.properties").inputStream().use { properties.load(it) }
    val flutterSdkPath = properties.getProperty("flutter.sdk")
    require(flutterSdkPath != null) {
        "flutter.sdk not set in local.properties"
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)

    repositories {
        google()
        mavenCentral()
        maven(url = uri("$flutterStorageBaseUrl/${flutterEngineRealm}download.flutter.io"))
        maven(url = uri("https://jitpack.io")) {
            content {
                includeGroup("com.github.davidliu")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("com.google.gms.google-services") version "4.4.3" apply false
}

include(":app")
