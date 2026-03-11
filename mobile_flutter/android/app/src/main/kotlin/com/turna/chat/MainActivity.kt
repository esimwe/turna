package com.turna.chat

import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Environment
import android.os.Build
import android.os.PowerManager
import android.provider.MediaStore
import android.telephony.TelephonyManager
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import me.leolin.shortcutbadger.ShortcutBadger
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var proximityWakeLock: PowerManager.WakeLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "turna/display"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        if (enabled) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(null)
                }

                "setProximityScreenLockEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    runOnUiThread {
                        try {
                            setProximityScreenLockEnabled(enabled)
                            result.success(null)
                        } catch (error: Throwable) {
                            result.success(null)
                        }
                    }
                }

                "setAppBadgeCount" -> {
                    val count = call.argument<Int>("count") ?: 0
                    runOnUiThread {
                        try {
                            if (count > 0) {
                                ShortcutBadger.applyCount(applicationContext, count)
                            } else {
                                ShortcutBadger.removeCount(applicationContext)
                            }
                            result.success(null)
                        } catch (error: Throwable) {
                            result.success(null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "turna/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getContextInfo" -> {
                    result.success(
                        mapOf(
                            "deviceModel" to listOfNotNull(
                                Build.MANUFACTURER?.trim()?.takeIf { it.isNotEmpty() },
                                Build.MODEL?.trim()?.takeIf { it.isNotEmpty() }
                            ).joinToString(" ").ifBlank { Build.DEVICE ?: "Android" },
                            "osVersion" to "Android ${Build.VERSION.RELEASE ?: Build.VERSION.SDK_INT}",
                            "appVersion" to resolveAppVersion(),
                            "localeTag" to resolveLocaleTag(),
                            "regionCode" to resolveRegionCode(),
                            "localeCountryIso" to resolveRegionCode(),
                            "simCountryIso" to resolveSimCountryIso(),
                            "networkCountryIso" to resolveNetworkCountryIso()
                        )
                    )
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "turna/media"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareFile" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_args", "Dosya yolu gerekli.", null)
                    } else {
                        shareFile(path, mimeType, result)
                    }
                }

                "saveToGallery" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_args", "Dosya yolu gerekli.", null)
                    } else {
                        saveToGallery(path, mimeType, result)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        releaseProximityWakeLock()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun setProximityScreenLockEnabled(enabled: Boolean) {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_PROXIMITY)) {
            releaseProximityWakeLock()
            return
        }

        if (!enabled) {
            releaseProximityWakeLock()
            return
        }

        val manager = getSystemService(POWER_SERVICE) as? PowerManager ?: return
        val wakeLock =
            proximityWakeLock
                ?: manager.newWakeLock(
                    PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                    "$packageName:turna-proximity",
                ).apply {
                    setReferenceCounted(false)
                    proximityWakeLock = this
                }
        if (!wakeLock.isHeld) {
            wakeLock.acquire()
        }
    }

    private fun releaseProximityWakeLock() {
        try {
            proximityWakeLock?.let { wakeLock ->
                if (wakeLock.isHeld) {
                    wakeLock.release()
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun shareFile(path: String, mimeType: String?, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "Dosya bulunamadı.", null)
            return
        }

        try {
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.turna.media",
                file
            )
            val intent =
                Intent(Intent.ACTION_SEND).apply {
                    type = mimeType?.takeIf { it.isNotBlank() } ?: "*/*"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            startActivity(Intent.createChooser(intent, "Paylaş"))
            result.success(null)
        } catch (error: Throwable) {
            result.error("share_failed", error.message, null)
        }
    }

    private fun saveToGallery(path: String, mimeType: String?, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "Dosya bulunamadı.", null)
            return
        }

        val resolvedMime = when {
            !mimeType.isNullOrBlank() -> mimeType
            file.extension.equals("mp4", ignoreCase = true) -> "video/mp4"
            file.extension.equals("mov", ignoreCase = true) -> "video/quicktime"
            else -> "image/jpeg"
        }
        val isVideo = resolvedMime.startsWith("video/")
        val collection =
            if (isVideo) {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }

        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
                put(MediaStore.MediaColumns.MIME_TYPE, resolvedMime)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        if (isVideo) {
                            "${Environment.DIRECTORY_MOVIES}/Turna"
                        } else {
                            "${Environment.DIRECTORY_PICTURES}/Turna"
                        }
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }

        val uri = contentResolver.insert(collection, values)
        if (uri == null) {
            result.error("save_failed", "Kayıt açılamadı.", null)
            return
        }

        try {
            contentResolver.openOutputStream(uri)?.use { output ->
                file.inputStream().use { input ->
                    input.copyTo(output)
                }
            } ?: throw IllegalStateException("Çıkış akışı açılamadı.")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            }
            result.success(null)
        } catch (error: Throwable) {
            contentResolver.delete(uri, null, null)
            result.error("save_failed", error.message, null)
        }
    }

    private fun resolveAppVersion(): String {
        return try {
            val packageInfo: PackageInfo =
                packageManager.getPackageInfo(packageName, 0)
            packageInfo.versionName ?: "1.0.0"
        } catch (_: Throwable) {
            "1.0.0"
        }
    }

    private fun resolveLocaleTag(): String {
        val locale =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                resources.configuration.locales[0] ?: Locale.getDefault()
            } else {
                @Suppress("DEPRECATION")
                resources.configuration.locale ?: Locale.getDefault()
            }
        return locale.toLanguageTag()
    }

    private fun resolveRegionCode(): String? {
        val locale =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                resources.configuration.locales[0] ?: Locale.getDefault()
            } else {
                @Suppress("DEPRECATION")
                resources.configuration.locale ?: Locale.getDefault()
            }
        val country = locale.country?.trim()?.uppercase(Locale.ROOT)
        return country?.takeIf { it.length == 2 }
    }

    private fun resolveSimCountryIso(): String? {
        return try {
            val manager = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager
            manager?.simCountryIso?.trim()?.uppercase(Locale.ROOT)?.takeIf { it.length == 2 }
        } catch (_: Throwable) {
            null
        }
    }

    private fun resolveNetworkCountryIso(): String? {
        return try {
            val manager = getSystemService(TELEPHONY_SERVICE) as? TelephonyManager
            manager?.networkCountryIso?.trim()?.uppercase(Locale.ROOT)?.takeIf { it.length == 2 }
        } catch (_: Throwable) {
            null
        }
    }
}
