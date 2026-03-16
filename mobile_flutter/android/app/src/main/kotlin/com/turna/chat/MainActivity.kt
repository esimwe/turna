package com.turna.chat

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.telephony.TelephonyManager
import android.view.WindowManager
import android.webkit.MimeTypeMap
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import me.leolin.shortcutbadger.ShortcutBadger
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    private var proximityWakeLock: PowerManager.WakeLock? = null
    private var pendingDocumentScanResult: MethodChannel.Result? = null
    private var pendingVideoProcessResult: MethodChannel.Result? = null
    private var shareTargetChannel: MethodChannel? = null
    private var isShareTargetBridgeReady: Boolean = false
    private var pendingSharedPayload: Map<String, Any?>? = null
    private val documentScanLauncher =
        registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { activityResult ->
            handleDocumentScanResult(activityResult.resultCode, activityResult.data)
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureIncomingSharedPayload(intent, notifyFlutter = false)
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

                "saveFile" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType")
                    val fileName = call.argument<String>("fileName")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_args", "Dosya yolu gerekli.", null)
                    } else {
                        saveFile(path, mimeType, fileName, result)
                    }
                }

                "processVideo" -> {
                    val path = call.argument<String>("path")
                    val transferMode = call.argument<String>("transferMode") ?: "standard"
                    val fileName = call.argument<String>("fileName")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_args", "Video yolu gerekli.", null)
                    } else {
                        processVideo(path, transferMode, fileName, result)
                    }
                }

                "scanDocument" -> {
                    runOnUiThread {
                        presentDocumentScanner(result)
                    }
                }

                "getPdfPageCount" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("invalid_args", "PDF yolu gerekli.", null)
                    } else {
                        getPdfPageCount(path, result)
                    }
                }

                "renderPdfPage" -> {
                    val path = call.argument<String>("path")
                    val pageIndex = call.argument<Int>("pageIndex")
                    val targetWidth = call.argument<Int>("targetWidth") ?: 1440
                    if (path.isNullOrBlank() || pageIndex == null) {
                        result.error("invalid_args", "PDF parametreleri eksik.", null)
                    } else {
                        renderPdfPage(path, pageIndex, targetWidth, result)
                    }
                }

                else -> result.notImplemented()
            }
        }

        val shareChannel =
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "turna/share_target",
            )
        shareChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "shareBridgeReady" -> {
                    isShareTargetBridgeReady = true
                    result.success(null)
                }

                "consumeInitialPayload" -> {
                    val payload = pendingSharedPayload
                    pendingSharedPayload = null
                    result.success(payload)
                }

                else -> result.notImplemented()
            }
        }
        shareTargetChannel = shareChannel
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIncomingSharedPayload(intent, notifyFlutter = true)
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

    private fun captureIncomingSharedPayload(intent: Intent?, notifyFlutter: Boolean) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return
        }
        val payload = buildSharedPayload(intent) ?: return
        pendingSharedPayload = payload
        if (notifyFlutter) {
            dispatchSharedPayloadIfReady()
        }
    }

    private fun dispatchSharedPayloadIfReady() {
        val payload = pendingSharedPayload ?: return
        val channel = shareTargetChannel ?: return
        if (!isShareTargetBridgeReady) return
        pendingSharedPayload = null
        runOnUiThread {
            channel.invokeMethod("sharedPayloadUpdated", payload)
        }
    }

    private fun buildSharedPayload(intent: Intent): Map<String, Any?>? {
        val resolvedItems = mutableListOf<Map<String, Any?>>()
        val fallbackMimeType = intent.type?.takeIf { it.isNotBlank() }
        val uris = mutableListOf<Uri>()

        when (intent.action) {
            Intent.ACTION_SEND -> {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let(uris::add)
                val clipData = intent.clipData
                if (uris.isEmpty() && clipData != null) {
                    for (index in 0 until clipData.itemCount) {
                        clipData.getItemAt(index).uri?.let(uris::add)
                    }
                }
            }

            Intent.ACTION_SEND_MULTIPLE -> {
                val extraUris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                if (!extraUris.isNullOrEmpty()) {
                    uris.addAll(extraUris)
                }
                val clipData = intent.clipData
                if (clipData != null) {
                    for (index in 0 until clipData.itemCount) {
                        clipData.getItemAt(index).uri?.let(uris::add)
                    }
                }
            }
        }

        for (uri in uris.distinct()) {
            copySharedUriToCache(uri, fallbackMimeType)?.let(resolvedItems::add)
        }

        if (resolvedItems.isEmpty()) return null
        return mapOf("items" to resolvedItems)
    }

    private fun copySharedUriToCache(
        uri: Uri,
        fallbackMimeType: String?,
    ): Map<String, Any?>? {
        return try {
            val sharedDir =
                File(cacheDir, "share_target").apply {
                    if (!exists()) {
                        mkdirs()
                    }
                }
            val originalFileName =
                resolveSharedDisplayName(uri)?.trim()?.takeIf { it.isNotEmpty() }
                    ?: "turna_share_${System.currentTimeMillis()}"
            val resolvedMimeType =
                contentResolver.getType(uri)?.takeIf { it.isNotBlank() }
                    ?: fallbackMimeType
                    ?: guessMimeTypeFromFileName(originalFileName)
                    ?: "application/octet-stream"
            val safeName = sanitizeSharedFileName(originalFileName)
            val cachedFile =
                File(sharedDir, "${System.currentTimeMillis()}_$safeName")
            val inputStream =
                if (uri.scheme == "file") {
                    File(uri.path ?: return null).inputStream()
                } else {
                    contentResolver.openInputStream(uri)
                }
            inputStream?.use { input ->
                FileOutputStream(cachedFile).use { output ->
                    input.copyTo(output)
                }
            } ?: return null

            mapOf(
                "path" to cachedFile.absolutePath,
                "fileName" to originalFileName,
                "mimeType" to resolvedMimeType,
                "sizeBytes" to cachedFile.length(),
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun resolveSharedDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") {
            return File(uri.path ?: return null).name
        }
        return try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && cursor.moveToFirst()) {
                        cursor.getString(index)
                    } else {
                        null
                    }
                }
        } catch (_: Throwable) {
            null
        }
    }

    private fun sanitizeSharedFileName(fileName: String): String {
        return fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }

    private fun guessMimeTypeFromFileName(fileName: String): String? {
        val extension = fileName.substringAfterLast('.', "").lowercase(Locale.US)
        if (extension.isBlank()) return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
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

    private fun saveFile(
        path: String,
        mimeType: String?,
        fileName: String?,
        result: MethodChannel.Result,
    ) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "Dosya bulunamadı.", null)
            return
        }

        val resolvedFileName =
            fileName?.trim()?.takeIf { it.isNotEmpty() } ?: file.name
        val resolvedMime =
            mimeType?.takeIf { it.isNotBlank() }
                ?: when {
                    resolvedFileName.endsWith(".pdf", ignoreCase = true) -> "application/pdf"
                    else -> "*/*"
                }
        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, resolvedFileName)
                put(MediaStore.MediaColumns.MIME_TYPE, resolvedMime)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        "${Environment.DIRECTORY_DOWNLOADS}/Turna",
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }

        val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        if (uri == null) {
            result.error("save_failed", "Dosya kaydedilemedi.", null)
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

    private fun getPdfPageCount(path: String, result: MethodChannel.Result) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "PDF bulunamadı.", null)
            return
        }

        try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { renderer ->
                    result.success(renderer.pageCount)
                }
            }
        } catch (error: Throwable) {
            result.error("invalid_pdf", error.message, null)
        }
    }

    private fun renderPdfPage(
        path: String,
        pageIndex: Int,
        targetWidth: Int,
        result: MethodChannel.Result,
    ) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "PDF bulunamadı.", null)
            return
        }

        try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { renderer ->
                    if (pageIndex < 0 || pageIndex >= renderer.pageCount) {
                        result.error("invalid_page", "PDF sayfası bulunamadı.", null)
                        return
                    }
                    renderer.openPage(pageIndex).use { page ->
                        val safeWidth = maxOf(1, targetWidth)
                        val scale = safeWidth.toFloat() / page.width.toFloat()
                        val bitmapWidth = safeWidth
                        val bitmapHeight = maxOf(1, (page.height * scale).toInt())
                        val bitmap =
                            Bitmap.createBitmap(
                                bitmapWidth,
                                bitmapHeight,
                                Bitmap.Config.ARGB_8888,
                            )
                        bitmap.eraseColor(android.graphics.Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        val output = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                        bitmap.recycle()
                        result.success(output.toByteArray())
                    }
                }
            }
        } catch (error: Throwable) {
            result.error("render_failed", error.message, null)
        }
    }

    private fun processVideo(
        path: String,
        transferMode: String,
        fileName: String?,
        result: MethodChannel.Result,
    ) {
        if (pendingVideoProcessResult != null) {
            result.error("busy", "Video zaten işleniyor.", null)
            return
        }

        val inputFile = File(path)
        if (!inputFile.exists()) {
            result.error("missing_file", "Video bulunamadı.", null)
            return
        }

        val normalizedMode = transferMode.trim().lowercase(Locale.US)
        val inputDimensions = resolveVideoDimensions(path)
        val targetHeight =
            when (normalizedMode) {
                "hd" -> minOf(inputDimensions.height.takeIf { it > 0 } ?: 1080, 1080)
                else -> minOf(inputDimensions.height.takeIf { it > 0 } ?: 720, 720)
            }
        val targetBitrate =
            when (normalizedMode) {
                "hd" -> 4_200_000
                else -> 1_800_000
            }

        val outputDir = File(cacheDir, "processed-videos").apply { mkdirs() }
        val outputFile =
            File(
                outputDir,
                "${System.currentTimeMillis()}_${buildProcessedVideoFileName(fileName ?: inputFile.name)}",
            )
        if (outputFile.exists()) {
            outputFile.delete()
        }

        val encoderFactory =
            DefaultEncoderFactory.Builder(this)
                .setRequestedVideoEncoderSettings(
                    VideoEncoderSettings.Builder().setBitrate(targetBitrate).build(),
                ).build()
        val targetEditedMediaItem =
            EditedMediaItem
                .Builder(MediaItem.fromUri(Uri.fromFile(inputFile)))
                .setEffects(
                    Effects(
                        emptyList(),
                        listOf(Presentation.createForHeight(maxOf(1, targetHeight))),
                    ),
                ).build()

        pendingVideoProcessResult = result
        val transformer =
            Transformer.Builder(this)
                .setEncoderFactory(encoderFactory)
                .addListener(
                    object : Transformer.Listener {
                        override fun onCompleted(
                            composition: Composition,
                            exportResult: ExportResult,
                        ) {
                            finishVideoProcessing(outputFile)
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException,
                        ) {
                            val pending = pendingVideoProcessResult ?: return
                            pendingVideoProcessResult = null
                            pending.error(
                                "process_failed",
                                exportException.message ?: "Video işlenemedi.",
                                null,
                            )
                        }
                    },
                ).build()

        transformer.start(targetEditedMediaItem, outputFile.absolutePath)
    }

    private fun finishVideoProcessing(outputFile: File) {
        val pending = pendingVideoProcessResult ?: return
        pendingVideoProcessResult = null
        val dimensions = resolveVideoDimensions(outputFile.absolutePath)
        pending.success(
            mapOf(
                "path" to outputFile.absolutePath,
                "fileName" to buildProcessedVideoFileName(outputFile.name),
                "mimeType" to "video/mp4",
                "sizeBytes" to outputFile.length(),
                "width" to dimensions.width,
                "height" to dimensions.height,
                "durationSeconds" to dimensions.durationSeconds,
            ),
        )
    }

    private fun resolveVideoDimensions(path: String): VideoDimensions {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(path)
            val width =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull() ?: 0
            val height =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull() ?: 0
            val rotation =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
            val durationMs =
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
            if (rotation == 90 || rotation == 270) {
                VideoDimensions(height, width, (durationMs / 1000L).toInt())
            } else {
                VideoDimensions(width, height, (durationMs / 1000L).toInt())
            }
        } catch (_: Throwable) {
            VideoDimensions(0, 0, 0)
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun buildProcessedVideoFileName(rawName: String): String {
        val normalized =
            rawName
                .trim()
                .replace(Regex("[\\\\/:*?\"<>|]"), "-")
                .ifEmpty { "video_${System.currentTimeMillis()}" }
        val extensionIndex = normalized.lastIndexOf('.')
        val stem =
            if (extensionIndex > 0) {
                normalized.substring(0, extensionIndex)
            } else {
                normalized
            }
        return "$stem.mp4"
    }

    private data class VideoDimensions(
        val width: Int,
        val height: Int,
        val durationSeconds: Int,
    )

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
