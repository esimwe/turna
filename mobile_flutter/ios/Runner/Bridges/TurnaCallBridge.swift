import CallKit
import Foundation
import PushKit
import UIKit
import flutter_callkit_incoming

final class TurnaCallBridge {
  private let pendingActionDefaultsKey = "turna_pending_native_call_action"
  private let activeUserDefaultsKey = "turna_call_preferences_active_user_id"
  private let silenceUnknownCallersKeyPrefix = "turna_call_silence_unknown_callers"
  private let knownContactIdsKeyPrefix = "turna_call_known_contact_ids"
  private let knownContactIdsReadyKeyPrefix = "turna_call_known_contact_ids_ready"
  private var voipRegistry: PKPushRegistry?

  func configureVoipRegistry(delegate: PKPushRegistryDelegate) {
    guard voipRegistry == nil else { return }
    let registry = PKPushRegistry(queue: .main)
    registry.delegate = delegate
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    TurnaLogger.debug("call", "voip registry configured")
  }

  func handleUpdatedCredentials(_ credentials: PKPushCredentials) {
    let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
    TurnaLogger.debug("call", "voip token updated", details: ["length": deviceToken.count])
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
  }

  func handleInvalidatePushToken() {
    TurnaLogger.debug("call", "voip token invalidated")
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func handleIncomingPush(
    _ payload: PKPushPayload,
    type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let payloadData = payload.dictionaryPayload as? [String: Any] ?? [:]
    let payloadType = (payloadData["type"] as? String ?? "incoming_call").lowercased()
    let callId = (payloadData["callId"] as? String) ?? (payloadData["id"] as? String) ?? ""

    TurnaLogger.debug(
      "call",
      "incoming voip push",
      details: [
        "appState": applicationStateDescription(),
        "callId": callId,
        "type": payloadType,
      ]
    )

    if payloadType == "call_ended" {
      let endData = flutter_callkit_incoming.Data(id: callId, nameCaller: "", handle: "", type: 0)
      SwiftFlutterCallkitIncomingPlugin.sharedInstance?.endCall(endData)
      completion()
      return
    }

    if UIApplication.shared.applicationState == .active {
      completion()
      return
    }

    let callerId = (payloadData["callerId"] as? String) ?? ""
    if shouldSilenceUnknownCaller(callerId: callerId) {
      TurnaLogger.info(
        "call",
        "incoming voip push silenced",
        details: ["callId": callId, "callerId": callerId]
      )
      completion()
      return
    }

    let callerName =
      (payloadData["nameCaller"] as? String) ??
      (payloadData["callerDisplayName"] as? String) ??
      "Turna"
    let handle = (payloadData["handle"] as? String) ?? callerName
    let isVideo =
      (payloadData["isVideo"] as? Bool) ??
      (((payloadData["callType"] as? String) ?? "").lowercased() == "video")

    let data = flutter_callkit_incoming.Data(
      id: callId,
      nameCaller: callerName,
      handle: handle,
      type: isVideo ? 1 : 0
    )
    data.extra = payloadData as NSDictionary

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
      completion()
    }
  }

  func persistPendingAction(_ action: String, call: Call) {
    let payload: [String: Any] = [
      "action": action,
      "body": call.data.toJSON(),
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
      TurnaLogger.warning("call", "pending action serialization failed", details: ["action": action])
      return
    }
    guard let raw = String(data: data, encoding: .utf8) else {
      TurnaLogger.warning("call", "pending action encoding failed", details: ["action": action])
      return
    }
    UserDefaults.standard.set(raw, forKey: pendingActionDefaultsKey)
    UserDefaults.standard.synchronize()
    TurnaLogger.debug("call", "persisted pending action", details: ["action": action])
  }

  private func shouldSilenceUnknownCaller(callerId: String) -> Bool {
    guard !callerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    guard
      let activeUserId = UserDefaults.standard.string(forKey: activeUserDefaultsKey)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !activeUserId.isEmpty
    else {
      return false
    }

    let silenceUnknownCallersKey = scopedDefaultsKey(
      prefix: silenceUnknownCallersKeyPrefix,
      userId: activeUserId
    )
    guard UserDefaults.standard.bool(forKey: silenceUnknownCallersKey) else {
      return false
    }

    let readyKey = scopedDefaultsKey(prefix: knownContactIdsReadyKeyPrefix, userId: activeUserId)
    guard UserDefaults.standard.bool(forKey: readyKey) else {
      return false
    }

    let contactIdsKey = scopedDefaultsKey(prefix: knownContactIdsKeyPrefix, userId: activeUserId)
    let knownContactIds = Set(UserDefaults.standard.stringArray(forKey: contactIdsKey) ?? [])
    return !knownContactIds.contains(callerId)
  }

  private func scopedDefaultsKey(prefix: String, userId: String) -> String {
    "\(prefix):\(userId)"
  }

  private func applicationStateDescription() -> String {
    switch UIApplication.shared.applicationState {
    case .active:
      return "active"
    case .inactive:
      return "inactive"
    case .background:
      return "background"
    @unknown default:
      return "unknown"
    }
  }
}
