import Flutter
import Foundation

final class TurnaLaunchBridge {
  private let launchScheme = "turna"
  private var launchChannel: FlutterMethodChannel?
  private var isBridgeReady = false
  private var pendingLaunchURL: String?

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    guard launchChannel == nil else { return }

    let channel = FlutterMethodChannel(
      name: "turna/launch",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "launchBridgeReady":
        self?.isBridgeReady = true
        TurnaLogger.debug(
          "launch",
          "bridge ready",
          details: ["hasURL": (self?.pendingLaunchURL != nil)]
        )
        self?.dispatchPendingLaunchURLIfReady()
        result(nil)
      case "consumeInitialUrl":
        let url = self?.pendingLaunchURL
        self?.pendingLaunchURL = nil
        TurnaLogger.debug(
          "launch",
          "consume initial url",
          details: ["hasURL": (url != nil)]
        )
        result(url)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    launchChannel = channel
    dispatchPendingLaunchURLIfReady()
  }

  @discardableResult
  func handleIncomingURL(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == launchScheme else {
      return false
    }
    pendingLaunchURL = url.absoluteString
    TurnaLogger.debug(
      "launch",
      "incoming url",
      details: ["url": sanitizedURLString(url)]
    )
    dispatchPendingLaunchURLIfReady()
    return true
  }

  private func dispatchPendingLaunchURLIfReady() {
    guard let url = pendingLaunchURL else {
      return
    }
    guard isBridgeReady else {
      TurnaLogger.debug("launch", "dispatch postponed", details: ["reason": "bridge_not_ready"])
      return
    }
    guard launchChannel != nil else {
      TurnaLogger.debug("launch", "dispatch postponed", details: ["reason": "channel_missing"])
      return
    }
    pendingLaunchURL = nil
    TurnaLogger.debug(
      "launch",
      "dispatching url to flutter",
      details: ["url": sanitizedURLString(URL(string: url) ?? URL(fileURLWithPath: url))]
    )
    launchChannel?.invokeMethod("launchUrlUpdated", arguments: url)
  }

  private func sanitizedURLString(_ url: URL) -> String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return url.absoluteString
    }
    if let items = components.queryItems, !items.isEmpty {
      components.queryItems = items.map { item in
        URLQueryItem(name: item.name, value: item.value == nil ? nil : "redacted")
      }
    }
    return components.string ?? url.absoluteString
  }
}
