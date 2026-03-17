package com.turna.chat

import android.content.Intent
import android.os.Bundle
import com.turna.chat.bridges.TurnaDeviceBridge
import com.turna.chat.bridges.TurnaDisplayBridge
import com.turna.chat.bridges.TurnaLaunchBridge
import com.turna.chat.bridges.TurnaLogger
import com.turna.chat.bridges.TurnaMediaBridge
import com.turna.chat.bridges.TurnaPdfBridge
import com.turna.chat.bridges.TurnaShareBridge
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    private val launchBridge = TurnaLaunchBridge()
    private val pdfBridge = TurnaPdfBridge()
    private val shareBridge by lazy {
        TurnaShareBridge(
            contentResolver = contentResolver,
            cacheDirProvider = { cacheDir },
        )
    }
    private val displayBridge by lazy { TurnaDisplayBridge(this) }
    private val deviceBridge by lazy { TurnaDeviceBridge(this) }
    private lateinit var mediaBridge: TurnaMediaBridge

    private val documentScanLauncher =
        registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { activityResult ->
            if (::mediaBridge.isInitialized) {
                mediaBridge.handleDocumentScanResult(activityResult.resultCode, activityResult.data)
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        mediaBridge = TurnaMediaBridge(this, documentScanLauncher)
        super.onCreate(savedInstanceState)
        TurnaLogger.configureDebugLogging(applicationInfo)
        shareBridge.captureIncomingIntent(intent, notifyFlutter = false)
        launchBridge.captureIncomingIntent(intent, notifyFlutter = false)
        TurnaLogger.info(
            "lifecycle",
            "activity created",
            mapOf("action" to (intent?.action ?: "null")),
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        displayBridge.configure(flutterEngine.dartExecutor.binaryMessenger)
        deviceBridge.configure(flutterEngine.dartExecutor.binaryMessenger)
        mediaBridge.configure(flutterEngine.dartExecutor.binaryMessenger, pdfBridge)
        shareBridge.configure(flutterEngine.dartExecutor.binaryMessenger)
        launchBridge.configure(flutterEngine.dartExecutor.binaryMessenger)
        TurnaLogger.info("lifecycle", "flutter bridges configured")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        shareBridge.captureIncomingIntent(intent, notifyFlutter = true)
        launchBridge.captureIncomingIntent(intent, notifyFlutter = true)
        TurnaLogger.info(
            "lifecycle",
            "new intent",
            mapOf("action" to (intent.action ?: "null")),
        )
    }

    override fun onDestroy() {
        displayBridge.release()
        super.onDestroy()
    }
}
