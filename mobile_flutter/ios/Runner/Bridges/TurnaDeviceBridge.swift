import Darwin
import Flutter
import Foundation
import UIKit

final class TurnaDeviceBridge {
  private var deviceChannel: FlutterMethodChannel?

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    guard deviceChannel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "turna/device",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getContextInfo":
        result(self?.buildContextPayload())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    deviceChannel = channel
  }

  private func buildContextPayload() -> [String: Any] {
    let locale = Locale.autoupdatingCurrent
    return [
      "deviceModel": resolveDeviceModel(),
      "osVersion": "iOS \(UIDevice.current.systemVersion)",
      "appVersion": resolveAppVersion(),
      "localeTag": locale.identifier,
      "regionCode": (locale.regionCode ?? "").uppercased(),
      "localeCountryIso": (locale.regionCode ?? "").uppercased(),
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
