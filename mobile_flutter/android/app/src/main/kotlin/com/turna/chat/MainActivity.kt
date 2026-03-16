package com.turna.chat

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.telephony.TelephonyManager
import android.view.WindowManager
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import me.leolin.shortcutbadger.ShortcutBadger
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    private var proximityWakeLock: PowerManager.WakeLock? = null
    private var pendingDocumentScanResult: MethodChannel.Result? = null
    private val documentScanLauncher =
        registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { activityResult ->
            handleDocumentScanResult(activityResult.resultCode, activityResult.data)
        }

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

                "scanDocument" -> {
                    runOnUiThread {
                        presentDocumentScanner(result)
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

    private fun presentDocumentScanner(result: MethodChannel.Result) {
        if (pendingDocumentScanResult != null) {
            result.error("busy", "Belge tarayıcı zaten açık.", null)
            return
        }

        val options =
            GmsDocumentScannerOptions.Builder()
                .setGalleryImportAllowed(false)
                .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
                .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
                .build()

        GmsDocumentScanning.getClient(options)
            .getStartScanIntent(this)
            .addOnSuccessListener { intentSender ->
                pendingDocumentScanResult = result
                try {
                    documentScanLauncher.launch(IntentSenderRequest.Builder(intentSender).build())
                } catch (error: Throwable) {
                    pendingDocumentScanResult = null
                    result.error("scan_failed", error.message, null)
                }
            }
            .addOnFailureListener { error ->
                result.error(
                    "scan_failed",
                    error.message ?: "Belge tarayıcı açılamadı.",
                    null
                )
            }
    }

    private fun handleDocumentScanResult(resultCode: Int, data: Intent?) {
        val pending = pendingDocumentScanResult ?: return
        pendingDocumentScanResult = null

        if (resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return
        }

        try {
            val scanResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
            val pdf = scanResult?.pdf
            if (pdf == null) {
                pending.error("scan_failed", "Tarama PDF olarak alınamadı.", null)
                return
            }

            val fileName = resolveDocumentDisplayName(pdf.uri) ?: buildScannedDocumentFileName()
            val cachedFile = copyDocumentUriToCache(pdf.uri, fileName)
            pending.success(
                mapOf(
                    "path" to cachedFile.absolutePath,
                    "fileName" to cachedFile.name,
                    "mimeType" to (contentResolver.getType(pdf.uri) ?: "application/pdf"),
                    "sizeBytes" to cachedFile.length(),
                    "pageCount" to pdf.pageCount,
                )
            )
        } catch (error: Throwable) {
            pending.error("scan_failed", error.message, null)
        }
    }

    private fun copyDocumentUriToCache(uri: android.net.Uri, fileName: String): File {
        val safeName = sanitizeDocumentFileName(fileName)
        val scansDir = File(cacheDir, "document-scans").apply { mkdirs() }
        val target = File(scansDir, "${System.currentTimeMillis()}_$safeName")

        val input =
            contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Tarama dosyası okunamadı.")
        input.use { stream ->
            FileOutputStream(target).use { output ->
                stream.copyTo(output)
            }
        }
        return target
    }

    private fun resolveDocumentDisplayName(uri: android.net.Uri): String? {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex >= 0 && cursor.moveToFirst()) {
                val rawName = cursor.getString(nameIndex)?.trim().orEmpty()
                if (rawName.isNotEmpty()) {
                    return rawName
                }
            }
        }
        return null
    }

    private fun buildScannedDocumentFileName(): String {
        return "scan_${System.currentTimeMillis()}.pdf"
    }

    private fun sanitizeDocumentFileName(fileName: String): String {
        val normalized =
            fileName
                .trim()
                .replace(Regex("[\\\\/:*?\"<>|]"), "-")
                .ifEmpty { buildScannedDocumentFileName() }
        return if (normalized.lowercase(Locale.US).endsWith(".pdf")) {
            normalized
        } else {
            "$normalized.pdf"
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
