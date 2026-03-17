package com.turna.chat.bridges

import android.content.pm.ApplicationInfo
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object TurnaLogger {
    private const val tag = "turna-native"
    private const val breadcrumbLimit = 120
    @Volatile private var debugLoggingEnabled = false
    private val formatter =
        SimpleDateFormat(
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            Locale.US,
        )
    private val breadcrumbs = ArrayDeque<String>()

    fun configureDebugLogging(applicationInfo: ApplicationInfo?) {
        debugLoggingEnabled =
            applicationInfo?.flags?.and(ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    fun debug(
        scope: String,
        message: String,
        details: Map<String, Any?> = emptyMap(),
    ) {
        log(Log.DEBUG, "debug", scope, message, details)
    }

    fun info(
        scope: String,
        message: String,
        details: Map<String, Any?> = emptyMap(),
    ) {
        log(Log.INFO, "info", scope, message, details)
    }

    fun warn(
        scope: String,
        message: String,
        details: Map<String, Any?> = emptyMap(),
    ) {
        log(Log.WARN, "warn", scope, message, details)
    }

    fun error(
        scope: String,
        message: String,
        details: Map<String, Any?> = emptyMap(),
    ) {
        log(Log.ERROR, "error", scope, message, details)
    }

    @Synchronized
    fun breadcrumbSnapshot(): List<String> = breadcrumbs.toList()

    @Synchronized
    private fun remember(line: String) {
        breadcrumbs.addLast(line)
        while (breadcrumbs.size > breadcrumbLimit) {
            breadcrumbs.removeFirst()
        }
    }

    private fun log(
        priority: Int,
        level: String,
        scope: String,
        message: String,
        details: Map<String, Any?>,
    ) {
        val line =
            buildString {
                append("[turna-native][")
                append(formatter.format(Date()))
                append("][")
                append(level)
                append("][")
                append(scope.ifBlank { "app" })
                append("] ")
                append(message)
                if (details.isNotEmpty()) {
                    append(" | {")
                    append(
                        details.entries
                            .sortedBy { it.key }
                            .joinToString(", ") { "${it.key}: ${it.value}" },
                    )
                    append("}")
                }
            }
        remember(line)
        if (priority == Log.DEBUG || priority == Log.INFO) {
            if (!debugLoggingEnabled) {
                return
            }
        }
        Log.println(priority, tag, line)
    }
}
