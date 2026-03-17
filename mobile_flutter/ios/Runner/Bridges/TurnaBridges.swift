import AVFAudio
import AVFoundation
import CallKit
import Darwin
import Flutter
import PDFKit
import Photos
import PushKit
import UIKit
import VisionKit
import flutter_callkit_incoming

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

final class TurnaCallBridge {
  private let pendingActionDefaultsKey = "turna_pending_native_call_action"
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

final class TurnaPdfBridge {
  func getPdfPageCount(path: String, result: @escaping FlutterResult) {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(FlutterError(code: "missing_file", message: "PDF bulunamadı.", details: nil))
      return
    }
    guard let document = PDFDocument(url: fileURL) else {
      result(FlutterError(code: "invalid_pdf", message: "PDF açılamadı.", details: nil))
      return
    }
    result(document.pageCount)
  }

  func renderPdfPage(
    path: String,
    pageIndex: Int,
    targetWidth: Int,
    result: @escaping FlutterResult
  ) {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(FlutterError(code: "missing_file", message: "PDF bulunamadı.", details: nil))
      return
    }
    guard let document = PDFDocument(url: fileURL) else {
      result(FlutterError(code: "invalid_pdf", message: "PDF açılamadı.", details: nil))
      return
    }
    guard let page = document.page(at: pageIndex) else {
      result(FlutterError(code: "invalid_page", message: "PDF sayfası bulunamadı.", details: nil))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      let pageBounds = page.bounds(for: .mediaBox)
      let width = max(1, CGFloat(targetWidth))
      let scale = width / max(pageBounds.width, 1)
      let outputSize = CGSize(
        width: width,
        height: max(1, pageBounds.height * scale)
      )
      let renderer = UIGraphicsImageRenderer(size: outputSize)
      let image = renderer.image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: outputSize))
        context.cgContext.saveGState()
        context.cgContext.translateBy(x: 0, y: outputSize.height)
        context.cgContext.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context.cgContext)
        context.cgContext.restoreGState()
      }
      guard let data = image.pngData() else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "render_failed",
              message: "PDF sayfası hazırlanamadı.",
              details: nil
            )
          )
        }
        return
      }
      DispatchQueue.main.async {
        result(FlutterStandardTypedData(bytes: data))
      }
    }
  }
}

final class TurnaMediaBridge: NSObject, VNDocumentCameraViewControllerDelegate {
  private let topMostViewControllerProvider: () -> UIViewController?
  private var mediaChannel: FlutterMethodChannel?
  private var statusCameraChannel: FlutterMethodChannel?
  private var pendingStatusCameraResult: FlutterResult?
  private var pendingDocumentScanResult: FlutterResult?
  private var pendingVideoProcessResult: FlutterResult?

  init(topMostViewControllerProvider: @escaping () -> UIViewController?) {
    self.topMostViewControllerProvider = topMostViewControllerProvider
  }

  func configure(binaryMessenger: FlutterBinaryMessenger, pdfBridge: TurnaPdfBridge) {
    guard mediaChannel == nil, statusCameraChannel == nil else { return }

    let mediaChannel = FlutterMethodChannel(
      name: "turna/media",
      binaryMessenger: binaryMessenger
    )
    mediaChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "Medya köprüsü hazır değil.", details: nil))
        return
      }
      switch call.method {
      case "shareFile":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "invalid_args", message: "Dosya yolu gerekli.", details: nil))
          return
        }
        self.shareFile(path: path, result: result)
      case "saveToGallery":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "invalid_args", message: "Dosya yolu gerekli.", details: nil))
          return
        }
        let mimeType = args["mimeType"] as? String
        self.saveToGallery(path: path, mimeType: mimeType, result: result)
      case "saveFile":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "invalid_args", message: "Dosya yolu gerekli.", details: nil))
          return
        }
        self.saveFile(path: path, result: result)
      case "processVideo":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "invalid_args", message: "Video yolu gerekli.", details: nil))
          return
        }
        let transferMode = (args["transferMode"] as? String) ?? "standard"
        let fileName = args["fileName"] as? String
        self.processVideo(
          path: path,
          transferMode: transferMode,
          fileName: fileName,
          result: result
        )
      case "scanDocument":
        self.presentDocumentScanner(result: result)
      case "getPdfPageCount":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "invalid_args", message: "PDF yolu gerekli.", details: nil))
          return
        }
        pdfBridge.getPdfPageCount(path: path, result: result)
      case "renderPdfPage":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          let pageIndex = args["pageIndex"] as? Int
        else {
          result(
            FlutterError(code: "invalid_args", message: "PDF parametreleri eksik.", details: nil)
          )
          return
        }
        let targetWidth = args["targetWidth"] as? Int ?? 1440
        pdfBridge.renderPdfPage(
          path: path,
          pageIndex: pageIndex,
          targetWidth: targetWidth,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.mediaChannel = mediaChannel

    let statusCameraChannel = FlutterMethodChannel(
      name: "turna/status_camera",
      binaryMessenger: binaryMessenger
    )
    statusCameraChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "Kamera ekranı açılamadı.", details: nil))
        return
      }
      switch call.method {
      case "present":
        guard self.pendingStatusCameraResult == nil else {
          result(FlutterError(code: "busy", message: "Kamera zaten açık.", details: nil))
          return
        }
        let args = call.arguments as? [String: Any]
        let mode = (args?["mode"] as? String ?? "photo").lowercased()
        self.presentStatusCamera(
          initialMode: mode == "video" ? .video : .photo,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.statusCameraChannel = statusCameraChannel
  }

  private func presentStatusCamera(
    initialMode: TurnaStatusCameraViewController.Mode,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let controller = self.topMostViewControllerProvider() else {
        result(FlutterError(code: "missing_view", message: "Kamera ekranı açılamadı.", details: nil))
        return
      }

      TurnaLogger.debug("media", "status camera present", details: ["mode": initialMode.rawValue])
      self.pendingStatusCameraResult = result
      let cameraController = TurnaStatusCameraViewController(initialMode: initialMode)
      cameraController.modalPresentationStyle = .fullScreen
      cameraController.onFinish = { [weak self] payload, error in
        guard let self else { return }
        let pending = self.pendingStatusCameraResult
        self.pendingStatusCameraResult = nil
        if let error {
          pending?(FlutterError(code: "camera_failed", message: error.localizedDescription, details: nil))
        } else {
          pending?(payload)
        }
      }
      controller.present(cameraController, animated: true)
    }
  }

  private func shareFile(path: String, result: @escaping FlutterResult) {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(FlutterError(code: "missing_file", message: "Dosya bulunamadı.", details: nil))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let controller = self.topMostViewControllerProvider() else {
        result(FlutterError(code: "missing_view", message: "Paylaşım ekranı açılamadı.", details: nil))
        return
      }
      let activity = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
      activity.completionWithItemsHandler = { _, _, _, _ in
        result(nil)
      }
      if let popover = activity.popoverPresentationController {
        popover.sourceView = controller.view
        popover.sourceRect = CGRect(
          x: controller.view.bounds.midX,
          y: controller.view.bounds.maxY - 40,
          width: 1,
          height: 1
        )
      }
      controller.present(activity, animated: true)
    }
  }

  private func saveToGallery(path: String, mimeType: String?, result: @escaping FlutterResult) {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(FlutterError(code: "missing_file", message: "Dosya bulunamadı.", details: nil))
      return
    }

    let lowerMimeType = (mimeType ?? "").lowercased()
    let isVideo = lowerMimeType.starts(with: "video/")

    let performSave = {
      let preparedURL = self.preparePhotosCompatibleURL(for: fileURL, mimeType: lowerMimeType) ?? fileURL
      if preparedURL != fileURL && !FileManager.default.fileExists(atPath: preparedURL.path) {
        result(
          FlutterError(code: "save_failed", message: "Geçici medya dosyası hazırlanamadı.", details: nil)
        )
        return
      }

      PHPhotoLibrary.shared().performChanges({
        if isVideo {
          PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: preparedURL)
        } else if let data = try? Data(contentsOf: preparedURL), let image = UIImage(data: data) {
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        } else {
          PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: preparedURL)
        }
      }) { success, error in
        if preparedURL != fileURL {
          try? FileManager.default.removeItem(at: preparedURL)
        }
        if let error {
          result(FlutterError(code: "save_failed", message: error.localizedDescription, details: nil))
          return
        }
        result(
          success
            ? nil
            : FlutterError(code: "save_failed", message: "Kaydetme tamamlanamadı.", details: nil)
        )
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        switch status {
        case .authorized, .limited:
          performSave()
        default:
          result(
            FlutterError(code: "permission_denied", message: "Fotoğraf izni verilmedi.", details: nil)
          )
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        switch status {
        case .authorized:
          performSave()
        default:
          result(
            FlutterError(code: "permission_denied", message: "Fotoğraf izni verilmedi.", details: nil)
          )
        }
      }
    }
  }

  private func saveFile(path: String, result: @escaping FlutterResult) {
    let fileURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(FlutterError(code: "missing_file", message: "Dosya bulunamadı.", details: nil))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let controller = self.topMostViewControllerProvider() else {
        result(FlutterError(code: "missing_view", message: "Kaydetme ekranı açılamadı.", details: nil))
        return
      }
      let picker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
      picker.modalPresentationStyle = .formSheet
      controller.present(picker, animated: true)
      result(nil)
    }
  }

  private func processVideo(
    path: String,
    transferMode: String,
    fileName: String?,
    result: @escaping FlutterResult
  ) {
    guard pendingVideoProcessResult == nil else {
      result(FlutterError(code: "busy", message: "Video zaten işleniyor.", details: nil))
      return
    }
    let inputURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: inputURL.path) else {
      result(FlutterError(code: "missing_file", message: "Video bulunamadı.", details: nil))
      return
    }

    let asset = AVURLAsset(url: inputURL)
    let normalizedMode = transferMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let preferredPreset =
      normalizedMode == "hd" ? AVAssetExportPreset1920x1080 : AVAssetExportPreset1280x720
    let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
    let presetName = compatiblePresets.contains(preferredPreset)
      ? preferredPreset
      : AVAssetExportPresetHighestQuality

    guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
      result(
        FlutterError(
          code: "process_failed",
          message: "Video dışa aktarma başlatılamadı.",
          details: nil
        )
      )
      return
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("mp4")
    try? FileManager.default.removeItem(at: outputURL)

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.metadata = []
    pendingVideoProcessResult = result

    exportSession.exportAsynchronously { [weak self] in
      guard let self else { return }
      let pending = self.pendingVideoProcessResult
      self.pendingVideoProcessResult = nil
      DispatchQueue.main.async {
        switch exportSession.status {
        case .completed:
          let exportedAsset = AVURLAsset(url: outputURL)
          let videoTrack = exportedAsset.tracks(withMediaType: .video).first
          let videoSize = self.resolveVideoSize(videoTrack)
          let durationSeconds = max(0, Int(round(CMTimeGetSeconds(exportedAsset.duration))))
          let attributes = try? FileManager.default.attributesOfItem(atPath: outputURL.path)
          let sizeBytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
          pending?([
            "path": outputURL.path,
            "fileName": self.buildProcessedVideoFileName(
              sourceName: fileName ?? inputURL.lastPathComponent
            ),
            "mimeType": "video/mp4",
            "sizeBytes": sizeBytes,
            "width": videoSize.width,
            "height": videoSize.height,
            "durationSeconds": durationSeconds,
          ])
        case .cancelled:
          pending?(
            FlutterError(
              code: "process_cancelled",
              message: "Video işleme iptal edildi.",
              details: nil
            )
          )
        default:
          pending?(
            FlutterError(
              code: "process_failed",
              message: exportSession.error?.localizedDescription ?? "Video işlenemedi.",
              details: nil
            )
          )
        }
      }
    }
  }

  private func presentDocumentScanner(result: @escaping FlutterResult) {
    guard pendingDocumentScanResult == nil else {
      result(FlutterError(code: "busy", message: "Belge tarayıcı zaten açık.", details: nil))
      return
    }
    guard VNDocumentCameraViewController.isSupported else {
      result(
        FlutterError(
          code: "unsupported",
          message: "Bu cihaz belge taramayı desteklemiyor.",
          details: nil
        )
      )
      return
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let controller = self.topMostViewControllerProvider() else {
        result(FlutterError(code: "missing_view", message: "Tarayıcı açılamadı.", details: nil))
        return
      }

      self.pendingDocumentScanResult = result
      let scanner = VNDocumentCameraViewController()
      scanner.delegate = self
      controller.present(scanner, animated: true)
    }
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true) { [weak self] in
      self?.finishDocumentScan(payload: nil, error: nil)
    }
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true) { [weak self] in
      self?.finishDocumentScan(payload: nil, error: error)
    }
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    controller.dismiss(animated: true) { [weak self] in
      self?.exportDocumentScan(scan)
    }
  }

  private func exportDocumentScan(_ scan: VNDocumentCameraScan) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }

      let pdfDocument = PDFDocument()
      pdfDocument.documentAttributes = [:]

      for index in 0 ..< scan.pageCount {
        autoreleasepool {
          let image = scan.imageOfPage(at: index)
          if let page = PDFPage(image: image) {
            pdfDocument.insert(page, at: pdfDocument.pageCount)
          }
        }
      }

      guard pdfDocument.pageCount > 0 else {
        DispatchQueue.main.async {
          self.finishDocumentScan(
            payload: nil,
            error: NSError(
              domain: "turna.media",
              code: -1,
              userInfo: [NSLocalizedDescriptionKey: "Taranan belge hazırlanamadı."]
            )
          )
        }
        return
      }

      let fileName = self.buildScannedDocumentFileName(from: scan.title)
      let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")

      guard pdfDocument.write(to: tempURL) else {
        DispatchQueue.main.async {
          self.finishDocumentScan(
            payload: nil,
            error: NSError(
              domain: "turna.media",
              code: -2,
              userInfo: [NSLocalizedDescriptionKey: "PDF dosyası oluşturulamadı."]
            )
          )
        }
        return
      }

      let attributes = try? FileManager.default.attributesOfItem(atPath: tempURL.path)
      let sizeBytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0

      DispatchQueue.main.async {
        self.finishDocumentScan(
          payload: [
            "path": tempURL.path,
            "fileName": fileName,
            "mimeType": "application/pdf",
            "sizeBytes": sizeBytes,
            "pageCount": scan.pageCount,
          ],
          error: nil
        )
      }
    }
  }

  private func finishDocumentScan(payload: [String: Any]?, error: Error?) {
    guard let pending = pendingDocumentScanResult else {
      return
    }
    pendingDocumentScanResult = nil
    if let error {
      pending(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
      return
    }
    pending(payload)
  }

  private func buildScannedDocumentFileName(from title: String) -> String {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseName: String
    if trimmed.isEmpty {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
      baseName = "scan_\(formatter.string(from: Date()))"
    } else {
      baseName = trimmed
    }

    let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    let cleaned = baseName.components(separatedBy: invalidCharacters).joined(separator: "-")
    let normalized = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    let safeName = normalized.isEmpty ? "scan" : normalized
    return safeName.lowercased().hasSuffix(".pdf") ? safeName : "\(safeName).pdf"
  }

  private func buildProcessedVideoFileName(sourceName: String) -> String {
    let trimmed = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseName = trimmed.isEmpty ? "video_\(Int(Date().timeIntervalSince1970))" : trimmed
    let nsName = baseName as NSString
    let stem = nsName.deletingPathExtension.isEmpty ? baseName : nsName.deletingPathExtension
    return "\(stem).mp4"
  }

  private func resolveVideoSize(_ track: AVAssetTrack?) -> (width: Int, height: Int) {
    guard let track else { return (0, 0) }
    let transformed = track.naturalSize.applying(track.preferredTransform)
    let width = max(0, Int(round(abs(transformed.width))))
    let height = max(0, Int(round(abs(transformed.height))))
    return (width, height)
  }

  private func preparePhotosCompatibleURL(for fileURL: URL, mimeType: String) -> URL? {
    let currentExt = fileURL.pathExtension.lowercased()
    if currentExt != "bin" {
      return fileURL
    }

    let ext = preferredMediaExtension(for: mimeType, originalURL: fileURL)
    guard !ext.isEmpty else { return fileURL }

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(ext)

    do {
      if FileManager.default.fileExists(atPath: tempURL.path) {
        try FileManager.default.removeItem(at: tempURL)
      }
      try FileManager.default.copyItem(at: fileURL, to: tempURL)
      return tempURL
    } catch {
      return nil
    }
  }

  private func preferredMediaExtension(for mimeType: String, originalURL: URL) -> String {
    let currentExt = originalURL.pathExtension.lowercased()
    if !currentExt.isEmpty && currentExt != "bin" {
      return currentExt
    }

    if mimeType.starts(with: "image/") {
      if mimeType.contains("png") { return "png" }
      if mimeType.contains("webp") { return "webp" }
      if mimeType.contains("heic") || mimeType.contains("heif") { return "heic" }
      if mimeType.contains("gif") { return "gif" }
      return "jpg"
    }

    if mimeType.starts(with: "video/") {
      if mimeType.contains("quicktime") { return "mov" }
      if mimeType.contains("webm") { return "webm" }
      if mimeType.contains("x-matroska") || mimeType.contains("mkv") { return "mkv" }
      return "mp4"
    }

    return ""
  }
}
