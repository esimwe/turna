import AVFAudio
import CallKit
import FirebaseCore
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private let pendingActionDefaultsKey = "flutter.turna_pending_native_call_action"
  private var displayChannel: FlutterMethodChannel?
  private var deviceChannel: FlutterMethodChannel?
  private var didConfigureDisplayChannel = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    GeneratedPluginRegistrant.register(with: self)

    let voipRegistry = PKPushRegistry(queue: .main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [.voIP]

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    configureDisplayChannelWhenReady()
    return didFinish
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    configureDisplayChannelWhenReady()
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let payloadData = payload.dictionaryPayload as? [String: Any] ?? [:]
    let payloadType = payloadData["type"] as? String ?? "incoming_call"
    let callId = (payloadData["callId"] as? String) ?? (payloadData["id"] as? String) ?? ""

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

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    persistPendingAction("accept", call)
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    persistPendingAction("decline", call)
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    persistPendingAction("end", call)
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {
    persistPendingAction("timeout", call)
  }

  func didActivateAudioSession(_ audioSession: AVAudioSession) {}

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}

  private func persistPendingAction(_ action: String, _ call: Call) {
    let payload: [String: Any] = [
      "action": action,
      "body": call.data.toJSON(),
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
      return
    }
    guard let raw = String(data: data, encoding: .utf8) else {
      return
    }
    UserDefaults.standard.set(raw, forKey: pendingActionDefaultsKey)
    UserDefaults.standard.synchronize()
  }

  private func configureDisplayChannelWhenReady(retryCount: Int = 0) {
    guard !didConfigureDisplayChannel else {
      return
    }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      if retryCount < 12 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.configureDisplayChannelWhenReady(retryCount: retryCount + 1)
        }
      }
      return
    }

    let channel = FlutterMethodChannel(
      name: "turna/display",
      binaryMessenger: controller.binaryMessenger
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

    let deviceChannel = FlutterMethodChannel(
      name: "turna/device",
      binaryMessenger: controller.binaryMessenger
    )
    deviceChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getContextInfo":
        result(self?.buildDeviceContextPayload())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.deviceChannel = deviceChannel
    didConfigureDisplayChannel = true
  }

  private func buildDeviceContextPayload() -> [String: Any] {
    let locale = Locale.autoupdatingCurrent
    return [
      "deviceModel": resolveDeviceModel(),
      "osVersion": "iOS \(UIDevice.current.systemVersion)",
      "appVersion": resolveAppVersion(),
      "localeTag": locale.identifier,
      "regionCode": (locale.regionCode ?? "").uppercased(),
      "localeCountryIso": (locale.regionCode ?? "").uppercased()
    ]
  }

  private func resolveAppVersion() -> String {
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
      !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return version
    }
    return "1.0.0"
  }

  private func resolveDeviceModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce(into: "") { result, element in
      guard let value = element.value as? Int8, value != 0 else { return }
      result.append(Character(UnicodeScalar(UInt8(value))))
    }

    if identifier.isEmpty {
      return UIDevice.current.model
    }
    return identifier
  }
}
