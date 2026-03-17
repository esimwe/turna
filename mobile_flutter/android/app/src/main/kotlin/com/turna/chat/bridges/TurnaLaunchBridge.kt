package com.turna.chat.bridges

import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class TurnaLaunchBridge {
    private var launchChannel: MethodChannel? = null
    private var isBridgeReady = false
    private var pendingLaunchUrl: String? = null

    fun configure(binaryMessenger: BinaryMessenger) {
        if (launchChannel != null) return
        val channel = MethodChannel(binaryMessenger, "turna/launch")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "launchBridgeReady" -> {
                    isBridgeReady = true
                    TurnaLogger.debug(
                        "launch",
                        "bridge ready",
                        mapOf("hasUrl" to (pendingLaunchUrl != null)),
                    )
                    dispatchPendingLaunchUrlIfReady()
                    result.success(null)
                }

                "consumeInitialUrl" -> {
                    val url = pendingLaunchUrl
                    pendingLaunchUrl = null
                    TurnaLogger.debug(
                        "launch",
                        "consume initial url",
                        mapOf("hasUrl" to (url != null)),
                    )
                    result.success(url)
                }

                else -> result.notImplemented()
            }
        }
        launchChannel = channel
        dispatchPendingLaunchUrlIfReady()
    }

    fun captureIncomingIntent(
        intent: Intent?,
        notifyFlutter: Boolean,
    ): Boolean {
        if (intent == null || intent.action != Intent.ACTION_VIEW) {
            return false
        }
        val data = intent.data ?: return false
        if (data.scheme?.lowercase(Locale.US) != "turna") {
            return false
        }
        pendingLaunchUrl = data.toString()
        TurnaLogger.debug(
            "launch",
            "incoming url",
            mapOf("url" to sanitizeUrl(data)),
        )
        if (notifyFlutter) {
            dispatchPendingLaunchUrlIfReady()
        }
        return true
    }

    private fun dispatchPendingLaunchUrlIfReady() {
        val url = pendingLaunchUrl ?: return
        val channel = launchChannel
        if (!isBridgeReady) {
            TurnaLogger.debug("launch", "dispatch postponed", mapOf("reason" to "bridge_not_ready"))
            return
        }
        if (channel == null) {
            TurnaLogger.debug("launch", "dispatch postponed", mapOf("reason" to "channel_missing"))
            return
        }
        pendingLaunchUrl = null
        TurnaLogger.debug(
            "launch",
            "dispatching url to flutter",
            mapOf("url" to sanitizeUrl(Uri.parse(url))),
        )
        channel.invokeMethod("launchUrlUpdated", url)
    }

    private fun sanitizeUrl(uri: Uri): String {
        val query =
            if (uri.queryParameterNames.isEmpty()) {
                null
            } else {
                uri.queryParameterNames.joinToString("&") { "$it=redacted" }
            }
        val base =
            buildString {
                append(uri.scheme ?: "")
                append("://")
                if (!uri.authority.isNullOrBlank()) {
                    append(uri.authority)
                }
                append(uri.path.orEmpty())
            }
        return if (query == null) base else "$base?$query"
    }
}
