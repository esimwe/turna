import Flutter
import Foundation

final class TurnaShareBridge {
  private let appGroupIdentifier = "group.com.turna.chat.shared"
  private let sharePayloadDefaultsKey = "turna.shared_payload"
  private let shareTargetScheme = "turna"
  private let shareTargetHost = "share-target"

  private var shareTargetChannel: FlutterMethodChannel?
  private var isBridgeReady = false
  private var pendingSharedPayload: [String: Any]?

  func loadPendingPayloadFromAppGroup() {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
      TurnaLogger.warning("share", "app group unavailable")
      return
    }
    if let payload = defaults.dictionary(forKey: sharePayloadDefaultsKey) {
      pendingSharedPayload = payload
      defaults.removeObject(forKey: sharePayloadDefaultsKey)
      defaults.synchronize()
      TurnaLogger.debug(
        "share",
        "loaded payload from app group",
        details: ["items": sharedItemCount(from: payload)]
      )
    } else {
      TurnaLogger.debug("share", "no payload found in app group")
    }
  }

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    guard shareTargetChannel == nil else { return }

    let channel = FlutterMethodChannel(
      name: "turna/share_target",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "shareBridgeReady":
        self?.isBridgeReady = true
        TurnaLogger.debug(
          "share",
          "bridge ready",
          details: [
            "hasPayload": (self?.pendingSharedPayload != nil),
            "items": self?.sharedItemCount(from: self?.pendingSharedPayload) ?? 0,
          ]
        )
        self?.dispatchPendingPayloadIfReady()
        result(nil)
      case "consumeInitialPayload":
        let payload = self?.pendingSharedPayload
        self?.pendingSharedPayload = nil
        TurnaLogger.debug(
          "share",
          "consume initial payload",
          details: [
            "hasPayload": (payload != nil),
            "items": self?.sharedItemCount(from: payload) ?? 0,
          ]
        )
        result(payload)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    shareTargetChannel = channel
    dispatchPendingPayloadIfReady()
  }

  @discardableResult
  func handleIncomingURL(_ url: URL) -> Bool {
    guard
      url.scheme?.lowercased() == shareTargetScheme,
      url.host?.lowercased() == shareTargetHost
    else {
      return false
    }
    TurnaLogger.debug("share", "incoming shared url", details: ["url": url.absoluteString])
    loadPendingPayloadFromAppGroup()
    dispatchPendingPayloadIfReady()
    return true
  }

  private func dispatchPendingPayloadIfReady() {
    guard let payload = pendingSharedPayload else {
      return
    }
    guard isBridgeReady else {
      TurnaLogger.debug(
        "share",
        "dispatch postponed",
        details: [
          "reason": "bridge_not_ready",
          "items": sharedItemCount(from: payload),
        ]
      )
      return
    }
    guard shareTargetChannel != nil else {
      TurnaLogger.debug(
        "share",
        "dispatch postponed",
        details: [
          "reason": "channel_missing",
          "items": sharedItemCount(from: payload),
        ]
      )
      return
    }
    pendingSharedPayload = nil
    TurnaLogger.debug(
      "share",
      "dispatching payload to flutter",
      details: ["items": sharedItemCount(from: payload)]
    )
    shareTargetChannel?.invokeMethod("sharedPayloadUpdated", arguments: payload)
  }

  private func sharedItemCount(from payload: [String: Any]?) -> Int {
    let items = payload?["items"] as? [[String: Any]]
    return items?.count ?? 0
  }
}
