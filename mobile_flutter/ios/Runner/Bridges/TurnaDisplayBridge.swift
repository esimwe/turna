import Flutter
import UIKit

final class TurnaDisplayBridge {
  private var displayChannel: FlutterMethodChannel?

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    guard displayChannel == nil else { return }

    let channel = FlutterMethodChannel(
      name: "turna/display",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setKeepScreenOn":
        let args = call.arguments as? [String: Any]
        let enabled = args?["enabled"] as? Bool ?? false
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = enabled
          result(nil)
        }
      case "setProximityScreenLockEnabled":
        let args = call.arguments as? [String: Any]
        let enabled = args?["enabled"] as? Bool ?? false
        DispatchQueue.main.async {
          UIDevice.current.isProximityMonitoringEnabled = enabled
          result(nil)
        }
      case "setAppBadgeCount":
        let args = call.arguments as? [String: Any]
        let count = args?["count"] as? Int ?? 0
        DispatchQueue.main.async {
          UIApplication.shared.applicationIconBadgeNumber = max(0, count)
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    displayChannel = channel
  }
}
