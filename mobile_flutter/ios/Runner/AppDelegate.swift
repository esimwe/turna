import AVFAudio
import CallKit
import FirebaseCore
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  private let launchBridge = TurnaLaunchBridge()
  private let shareBridge = TurnaShareBridge()
  private let callBridge = TurnaCallBridge()
  private let deviceBridge = TurnaDeviceBridge()
  private let pdfBridge = TurnaPdfBridge()
  private lazy var mediaBridge = TurnaMediaBridge(topMostViewControllerProvider: { [weak self] in
    self?.topMostViewController()
  })

  private var displayChannel: FlutterMethodChannel?
  private var didConfigureFlutterChannels = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    GeneratedPluginRegistrant.register(with: self)
    callBridge.configureVoipRegistry(delegate: self)

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    shareBridge.loadPendingPayloadFromAppGroup()

    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    TurnaLogger.info("lifecycle", "did finish launching")
    configureFlutterChannelsWhenReady()
    return didFinish
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    configureFlutterChannelsWhenReady()
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if handleIncomingURL(url, source: "application_open_url") {
      return true
    }
    return super.application(application, open: url, options: options)
  }

  @discardableResult
  func handleIncomingURL(_ url: URL, source: String = "unknown") -> Bool {
    if shareBridge.handleIncomingURL(url) {
      TurnaLogger.info(
        "lifecycle",
        "handled incoming url",
        details: ["source": source, "type": "share"]
      )
      return true
    }

    if launchBridge.handleIncomingURL(url) {
      TurnaLogger.info(
        "lifecycle",
        "handled incoming url",
        details: ["source": source, "type": "launch"]
      )
      return true
    }

    TurnaLogger.debug(
      "lifecycle",
      "incoming url ignored",
      details: ["source": source, "url": url.absoluteString]
    )
    return false
  }

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    callBridge.handleUpdatedCredentials(credentials)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    callBridge.handleInvalidatePushToken()
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    callBridge.handleIncomingPush(payload, type: type, completion: completion)
  }

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    callBridge.persistPendingAction("accept", call: call)
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    callBridge.persistPendingAction("decline", call: call)
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    callBridge.persistPendingAction("end", call: call)
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {
    callBridge.persistPendingAction("timeout", call: call)
  }

  func didActivateAudioSession(_ audioSession: AVAudioSession) {}

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {}

  private func configureFlutterChannelsWhenReady(retryCount: Int = 0) {
    guard !didConfigureFlutterChannels else {
      return
    }
    guard let controller = rootFlutterViewController() else {
      if retryCount < 12 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          self?.configureFlutterChannelsWhenReady(retryCount: retryCount + 1)
        }
      } else {
        TurnaLogger.warning("lifecycle", "flutter root controller unavailable")
      }
      return
    }

    configureDisplayChannel(binaryMessenger: controller.binaryMessenger)
    deviceBridge.configure(binaryMessenger: controller.binaryMessenger)
    mediaBridge.configure(binaryMessenger: controller.binaryMessenger, pdfBridge: pdfBridge)
    shareBridge.configure(binaryMessenger: controller.binaryMessenger)
    launchBridge.configure(binaryMessenger: controller.binaryMessenger)
    didConfigureFlutterChannels = true
    TurnaLogger.info("lifecycle", "flutter bridges configured")
  }

  private func configureDisplayChannel(binaryMessenger: FlutterBinaryMessenger) {
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

  private func rootFlutterViewController() -> FlutterViewController? {
    topMostViewController() as? FlutterViewController
  }

  private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
  }

  private func topMostViewController(from controller: UIViewController? = nil) -> UIViewController? {
    let rootController = controller ?? keyWindow()?.rootViewController
    if let navigation = rootController as? UINavigationController {
      return topMostViewController(from: navigation.visibleViewController)
    }
    if let tab = rootController as? UITabBarController {
      return topMostViewController(from: tab.selectedViewController)
    }
    if let presented = rootController?.presentedViewController {
      return topMostViewController(from: presented)
    }
    return rootController
  }
}
