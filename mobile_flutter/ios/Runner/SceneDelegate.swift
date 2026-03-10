import Flutter
import UIKit
import flutter_contacts

class SceneDelegate: FlutterSceneDelegate {
  private static var contactsPluginRegistered = false
  private var displayChannel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
      appDelegate.window = window
    }
    registerDeferredPluginsIfNeeded()
    configureDisplayChannel()
  }

  private func registerDeferredPluginsIfNeeded() {
    guard !Self.contactsPluginRegistered else {
      return
    }
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }
    guard let registrar = controller.registrar(forPlugin: "FlutterContactsPlugin") else {
      return
    }

    FlutterContactsPlugin.register(with: registrar)
    Self.contactsPluginRegistered = true
  }

  private func configureDisplayChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
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
  }
}
