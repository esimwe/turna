package com.turna.chat.bridges

import android.app.Activity
import android.content.pm.PackageManager
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import me.leolin.shortcutbadger.ShortcutBadger

class TurnaDisplayBridge(
    private val activity: Activity,
) {
    private var displayChannel: MethodChannel? = null
    private var proximityWakeLock: PowerManager.WakeLock? = null

    fun configure(binaryMessenger: BinaryMessenger) {
        if (displayChannel != null) return
        val channel = MethodChannel(binaryMessenger, "turna/display")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setKeepScreenOn" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    activity.runOnUiThread {
                        if (enabled) {
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                }

                "setProximityScreenLockEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    activity.runOnUiThread {
                        try {
                            setProximityScreenLockEnabled(enabled)
                            result.success(null)
                        } catch (_: Throwable) {
                            result.success(null)
                        }
                    }
                }

                "setAppBadgeCount" -> {
                    val count = call.argument<Int>("count") ?: 0
                    activity.runOnUiThread {
                        try {
                            if (count > 0) {
                                ShortcutBadger.applyCount(activity.applicationContext, count)
                            } else {
                                ShortcutBadger.removeCount(activity.applicationContext)
                            }
                            result.success(null)
                        } catch (_: Throwable) {
                            result.success(null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
        displayChannel = channel
    }

    fun release() {
        releaseProximityWakeLock()
    }

    @Suppress("DEPRECATION")
    private fun setProximityScreenLockEnabled(enabled: Boolean) {
        if (!activity.packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_PROXIMITY)) {
            releaseProximityWakeLock()
            return
        }

        if (!enabled) {
            releaseProximityWakeLock()
            return
        }

        val manager = activity.getSystemService(Activity.POWER_SERVICE) as? PowerManager ?: return
        val wakeLock =
            proximityWakeLock
                ?: manager.newWakeLock(
                    PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                    "${activity.packageName}:turna-proximity",
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
}
