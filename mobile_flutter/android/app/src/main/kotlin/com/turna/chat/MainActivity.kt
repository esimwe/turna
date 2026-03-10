package com.turna.chat

import android.content.pm.PackageInfo
import android.os.Build
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import me.leolin.shortcutbadger.ShortcutBadger
import java.util.Locale

class MainActivity : FlutterActivity() {
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
