import AVFAudio
import AVFoundation
import CallKit
import FirebaseCore
import Flutter
import Photos
import PDFKit
import PushKit
import UIKit
import UserNotifications
import VisionKit
import flutter_callkit_incoming
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate, VNDocumentCameraViewControllerDelegate {
  private let pendingActionDefaultsKey = "flutter.turna_pending_native_call_action"
  private var displayChannel: FlutterMethodChannel?
  private var deviceChannel: FlutterMethodChannel?
  private var mediaChannel: FlutterMethodChannel?
  private var statusCameraChannel: FlutterMethodChannel?
  private var didConfigureDisplayChannel = false
  private var pendingStatusCameraResult: FlutterResult?
  private var pendingDocumentScanResult: FlutterResult?

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

    let mediaChannel = FlutterMethodChannel(
      name: "turna/media",
      binaryMessenger: controller.binaryMessenger
    )
    mediaChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "shareFile":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(
            FlutterError(code: "invalid_args", message: "Dosya yolu gerekli.", details: nil)
          )
          return
        }
        self?.shareFile(path: path, result: result)
      case "saveToGallery":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(
            FlutterError(code: "invalid_args", message: "Dosya yolu gerekli.", details: nil)
          )
          return
        }
        let mimeType = args["mimeType"] as? String
        self?.saveToGallery(path: path, mimeType: mimeType, result: result)
      case "scanDocument":
        self?.presentDocumentScanner(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.mediaChannel = mediaChannel

    let statusCameraChannel = FlutterMethodChannel(
      name: "turna/status_camera",
      binaryMessenger: controller.binaryMessenger
    )
    statusCameraChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(code: "unavailable", message: "Kamera ekranı açılamadı.", details: nil)
        )
        return
      }
      switch call.method {
      case "present":
        guard self.pendingStatusCameraResult == nil else {
          result(
            FlutterError(
              code: "busy",
              message: "Kamera zaten açık.",
              details: nil
            )
          )
          return
        }
        let args = call.arguments as? [String: Any]
        let mode = (args?["mode"] as? String ?? "photo").lowercased()
        self.presentStatusCamera(initialMode: mode == "video" ? .video : .photo, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.statusCameraChannel = statusCameraChannel
    didConfigureDisplayChannel = true
  }

  private func presentStatusCamera(
    initialMode: TurnaStatusCameraViewController.Mode,
    result: @escaping FlutterResult
  ) {
    print("[turna-mobile] native status camera present | {mode: \(initialMode.rawValue)}")
    guard let controller = topMostViewController() else {
      result(
        FlutterError(code: "missing_view", message: "Kamera ekranı açılamadı.", details: nil)
      )
      return
    }

    pendingStatusCameraResult = result
    let cameraController = TurnaStatusCameraViewController(initialMode: initialMode)
    cameraController.modalPresentationStyle = .fullScreen
    cameraController.onFinish = { [weak self] payload, error in
      guard let self else { return }
      let pending = self.pendingStatusCameraResult
      self.pendingStatusCameraResult = nil
      if let error {
        pending?(
          FlutterError(code: "camera_failed", message: error.localizedDescription, details: nil)
        )
      } else {
        pending?(payload)
      }
    }
    DispatchQueue.main.async {
      controller.present(cameraController, animated: true)
    }
  }

  private func shareFile(path: String, result: @escaping FlutterResult) {
    let fileUrl = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileUrl.path) else {
      result(FlutterError(code: "missing_file", message: "Dosya bulunamadı.", details: nil))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let controller = self?.topMostViewController() else {
        result(
          FlutterError(code: "missing_view", message: "Paylaşım ekranı açılamadı.", details: nil)
        )
        return
      }
      let activity = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
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
    let fileUrl = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: fileUrl.path) else {
      result(FlutterError(code: "missing_file", message: "Dosya bulunamadı.", details: nil))
      return
    }

    let lowerMimeType = (mimeType ?? "").lowercased()
    let isVideo = lowerMimeType.starts(with: "video/")

    let performSave = {
      let preparedUrl = self.preparePhotosCompatibleUrl(for: fileUrl, mimeType: lowerMimeType) ?? fileUrl
      if preparedUrl != fileUrl && !FileManager.default.fileExists(atPath: preparedUrl.path) {
        result(
          FlutterError(code: "save_failed", message: "Geçici medya dosyası hazırlanamadı.", details: nil)
        )
        return
      }

      PHPhotoLibrary.shared().performChanges({
        if isVideo {
          PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: preparedUrl)
        } else if let data = try? Data(contentsOf: preparedUrl), let image = UIImage(data: data) {
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        } else {
          PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: preparedUrl)
        }
      }) { success, error in
        if preparedUrl != fileUrl {
          try? FileManager.default.removeItem(at: preparedUrl)
        }
        if let error {
          result(
            FlutterError(code: "save_failed", message: error.localizedDescription, details: nil)
          )
          return
        }
        result(success ? nil : FlutterError(code: "save_failed", message: "Kaydetme tamamlanamadı.", details: nil))
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

  private func presentDocumentScanner(result: @escaping FlutterResult) {
    guard pendingDocumentScanResult == nil else {
      result(
        FlutterError(code: "busy", message: "Belge tarayıcı zaten açık.", details: nil)
      )
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
    guard let controller = topMostViewController() else {
      result(
        FlutterError(code: "missing_view", message: "Tarayıcı açılamadı.", details: nil)
      )
      return
    }

    pendingDocumentScanResult = result
    let scanner = VNDocumentCameraViewController()
    scanner.delegate = self
    DispatchQueue.main.async {
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
      let tempUrl = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("pdf")

      guard pdfDocument.write(to: tempUrl) else {
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

      let attributes = try? FileManager.default.attributesOfItem(atPath: tempUrl.path)
      let sizeBytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0

      DispatchQueue.main.async {
        self.finishDocumentScan(
          payload: [
            "path": tempUrl.path,
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
      pending(
        FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil)
      )
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

  private func preparePhotosCompatibleUrl(for fileUrl: URL, mimeType: String) -> URL? {
    let currentExt = fileUrl.pathExtension.lowercased()
    if currentExt != "bin" {
      return fileUrl
    }

    let ext = preferredMediaExtension(for: mimeType, originalUrl: fileUrl)
    guard !ext.isEmpty else { return fileUrl }

    let tempUrl = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension(ext)

    do {
      if FileManager.default.fileExists(atPath: tempUrl.path) {
        try FileManager.default.removeItem(at: tempUrl)
      }
      try FileManager.default.copyItem(at: fileUrl, to: tempUrl)
      return tempUrl
    } catch {
      return nil
    }
  }

  private func preferredMediaExtension(for mimeType: String, originalUrl: URL) -> String {
    let currentExt = originalUrl.pathExtension.lowercased()
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

  private func topMostViewController(
    from controller: UIViewController? = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
  ) -> UIViewController? {
    if let navigation = controller as? UINavigationController {
      return topMostViewController(from: navigation.visibleViewController)
    }
    if let tab = controller as? UITabBarController {
      return topMostViewController(from: tab.selectedViewController)
    }
    if let presented = controller?.presentedViewController {
      return topMostViewController(from: presented)
    }
    return controller
  }
}
