package com.turna.chat.bridges

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class TurnaShareBridge(
    private val contentResolver: ContentResolver,
    private val cacheDirProvider: () -> File,
) {
    private var shareTargetChannel: MethodChannel? = null
    private var isBridgeReady = false
    private var pendingSharedPayload: Map<String, Any?>? = null

    fun configure(binaryMessenger: BinaryMessenger) {
        if (shareTargetChannel != null) return
        val channel = MethodChannel(binaryMessenger, "turna/share_target")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "shareBridgeReady" -> {
                    isBridgeReady = true
                    TurnaLogger.debug(
                        "share",
                        "bridge ready",
                        mapOf(
                            "hasPayload" to (pendingSharedPayload != null),
                            "items" to sharedItemCount(pendingSharedPayload),
                        ),
                    )
                    dispatchSharedPayloadIfReady()
                    result.success(null)
                }

                "consumeInitialPayload" -> {
                    val payload = pendingSharedPayload
                    pendingSharedPayload = null
                    TurnaLogger.debug(
                        "share",
                        "consume initial payload",
                        mapOf(
                            "hasPayload" to (payload != null),
                            "items" to sharedItemCount(payload),
                        ),
                    )
                    result.success(payload)
                }

                else -> result.notImplemented()
            }
        }
        shareTargetChannel = channel
        dispatchSharedPayloadIfReady()
    }

    fun captureIncomingIntent(
        intent: Intent?,
        notifyFlutter: Boolean,
    ): Boolean {
        if (intent == null) return false
        val action = intent.action ?: return false
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return false
        }
        val payload = buildSharedPayload(intent) ?: return false
        pendingSharedPayload = payload
        TurnaLogger.debug(
            "share",
            "incoming share intent captured",
            mapOf("items" to sharedItemCount(payload)),
        )
        if (notifyFlutter) {
            dispatchSharedPayloadIfReady()
        }
        return true
    }

    private fun dispatchSharedPayloadIfReady() {
        val payload = pendingSharedPayload ?: return
        val channel = shareTargetChannel
        if (!isBridgeReady) {
            TurnaLogger.debug(
                "share",
                "dispatch postponed",
                mapOf(
                    "reason" to "bridge_not_ready",
                    "items" to sharedItemCount(payload),
                ),
            )
            return
        }
        if (channel == null) {
            TurnaLogger.debug(
                "share",
                "dispatch postponed",
                mapOf(
                    "reason" to "channel_missing",
                    "items" to sharedItemCount(payload),
                ),
            )
            return
        }
        pendingSharedPayload = null
        TurnaLogger.debug(
            "share",
            "dispatching payload to flutter",
            mapOf("items" to sharedItemCount(payload)),
        )
        channel.invokeMethod("sharedPayloadUpdated", payload)
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
                File(cacheDirProvider(), "share_target").apply {
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
        } catch (error: Throwable) {
            TurnaLogger.warn(
                "share",
                "shared item copy failed",
                mapOf("error" to (error.message ?: "unknown")),
            )
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

    private fun sharedItemCount(payload: Map<String, Any?>?): Int {
        val items = payload?.get("items") as? List<*>
        return items?.size ?: 0
    }
}
