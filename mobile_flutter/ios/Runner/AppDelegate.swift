import AVFAudio
import AVFoundation
import CallKit
import FirebaseCore
import Flutter
import Photos
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
  private var mediaChannel: FlutterMethodChannel?
  private var statusCameraChannel: FlutterMethodChannel?
  private var didConfigureDisplayChannel = false
  private var pendingStatusCameraResult: FlutterResult?

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

private final class TurnaStatusCameraPreviewView: UIView {
  override class var layerClass: AnyClass {
    AVCaptureVideoPreviewLayer.self
  }

  var previewLayer: AVCaptureVideoPreviewLayer {
    guard let layer = layer as? AVCaptureVideoPreviewLayer else {
      fatalError("Expected AVCaptureVideoPreviewLayer")
    }
    return layer
  }
}

private final class TurnaStatusCameraViewController: UIViewController,
  AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate
{
  enum Mode: String {
    case photo
    case video
  }

  var onFinish: (([String: Any]?, Error?) -> Void)?

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "turna.status.camera.session")
  private let photoOutput = AVCapturePhotoOutput()
  private let movieOutput = AVCaptureMovieFileOutput()
  private let previewView = TurnaStatusCameraPreviewView()
  private let dimOverlayView = UIView()

  private var currentMode: Mode
  private var currentPosition: AVCaptureDevice.Position = .back
  private var videoInput: AVCaptureDeviceInput?
  private var audioInput: AVCaptureDeviceInput?
  private var configuredSession = false
  private var currentFlashMode: AVCaptureDevice.FlashMode = .off
  private var finished = false
  private var cancelPendingAfterRecording = false
  private var recordingTimer: Timer?
  private var recordingStartedAt: Date?

  private lazy var closeButton = makeCircleButton(
    systemName: "xmark",
    action: #selector(handleClosePressed)
  )
  private lazy var flashButton = makeCircleButton(
    systemName: "bolt.slash.fill",
    action: #selector(handleFlashPressed)
  )
  private lazy var flipButton = makeCircleButton(
    systemName: "arrow.triangle.2.circlepath.camera",
    action: #selector(handleFlipPressed)
  )
  private lazy var shutterButton = makeShutterButton(action: #selector(handleShutterPressed))
  private let timerLabel = UILabel()
  private let controlsContainer = UIView()
  private let topBar = UIStackView()
  private let bottomBar = UIStackView()
  private let modeContainer = UIStackView()
  private let photoModeButton = UIButton(type: .system)
  private let videoModeButton = UIButton(type: .system)

  init(initialMode: Mode) {
    self.currentMode = initialMode
    super.init(nibName: nil, bundle: nil)
    modalPresentationCapturesStatusBarAppearance = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var preferredStatusBarStyle: UIStatusBarStyle {
    .lightContent
  }

  override var prefersStatusBarHidden: Bool {
    false
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .black
    previewView.previewLayer.videoGravity = .resizeAspectFill
    previewView.previewLayer.session = session
    buildInterface()
    updateModeUI()
    requestCameraAccessAndConfigure()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    sessionQueue.async { [weak self] in
      guard let self, self.configuredSession, !self.session.isRunning else { return }
      self.session.startRunning()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    invalidateRecordingTimer()
    sessionQueue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewView.previewLayer.frame = previewView.bounds
    if let connection = previewView.previewLayer.connection, connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }
  }

  private func buildInterface() {
    previewView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(previewView)
    NSLayoutConstraint.activate([
      previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      previewView.topAnchor.constraint(equalTo: view.topAnchor),
      previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    dimOverlayView.translatesAutoresizingMaskIntoConstraints = false
    dimOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.08)
    dimOverlayView.isUserInteractionEnabled = false
    view.addSubview(dimOverlayView)
    NSLayoutConstraint.activate([
      dimOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      dimOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      dimOverlayView.topAnchor.constraint(equalTo: view.topAnchor),
      dimOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])

    topBar.axis = .horizontal
    topBar.alignment = .center
    topBar.spacing = 12
    topBar.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(topBar)

    topBar.addArrangedSubview(closeButton)
    topBar.addArrangedSubview(UIView())
    topBar.addArrangedSubview(flashButton)

    controlsContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(controlsContainer)

    bottomBar.axis = .horizontal
    bottomBar.alignment = .center
    bottomBar.distribution = .equalCentering
    bottomBar.translatesAutoresizingMaskIntoConstraints = false
    controlsContainer.addSubview(bottomBar)

    let leftSpacer = UIView()
    leftSpacer.translatesAutoresizingMaskIntoConstraints = false
    leftSpacer.widthAnchor.constraint(equalToConstant: 54).isActive = true

    bottomBar.addArrangedSubview(leftSpacer)
    bottomBar.addArrangedSubview(shutterButton)
    bottomBar.addArrangedSubview(flipButton)

    timerLabel.translatesAutoresizingMaskIntoConstraints = false
    timerLabel.textColor = .white
    timerLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
    timerLabel.textAlignment = .center
    timerLabel.alpha = 0
    controlsContainer.addSubview(timerLabel)

    modeContainer.axis = .horizontal
    modeContainer.alignment = .center
    modeContainer.spacing = 18
    modeContainer.translatesAutoresizingMaskIntoConstraints = false
    modeContainer.backgroundColor = UIColor.black.withAlphaComponent(0.38)
    modeContainer.layer.cornerRadius = 22
    modeContainer.isLayoutMarginsRelativeArrangement = true
    modeContainer.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    controlsContainer.addSubview(modeContainer)

    configureModeButton(photoModeButton, title: "FOTOGRAF", action: #selector(handlePhotoModePressed))
    configureModeButton(videoModeButton, title: "VIDEO", action: #selector(handleVideoModePressed))
    modeContainer.addArrangedSubview(videoModeButton)
    modeContainer.addArrangedSubview(photoModeButton)

    NSLayoutConstraint.activate([
      topBar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      topBar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),

      controlsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      controlsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
      controlsContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

      timerLabel.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
      timerLabel.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -16),

      bottomBar.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor),
      bottomBar.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor),
      bottomBar.bottomAnchor.constraint(equalTo: modeContainer.topAnchor, constant: -18),

      modeContainer.centerXAnchor.constraint(equalTo: controlsContainer.centerXAnchor),
      modeContainer.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor),
    ])
  }

  private func makeCircleButton(systemName: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = .white
    button.backgroundColor = UIColor.black.withAlphaComponent(0.34)
    button.layer.cornerRadius = 23
    button.setImage(UIImage(systemName: systemName), for: .normal)
    button.addTarget(self, action: action, for: .touchUpInside)
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 46),
      button.heightAnchor.constraint(equalToConstant: 46),
    ])
    return button
  }

  private func makeShutterButton(action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.tintColor = .clear
    button.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    button.layer.cornerRadius = 42
    button.layer.borderColor = UIColor.white.withAlphaComponent(0.95).cgColor
    button.layer.borderWidth = 4
    button.addTarget(self, action: action, for: .touchUpInside)
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 84),
      button.heightAnchor.constraint(equalToConstant: 84),
    ])

    let inner = UIView()
    inner.translatesAutoresizingMaskIntoConstraints = false
    inner.backgroundColor = .white
    inner.layer.cornerRadius = 31
    inner.isUserInteractionEnabled = false
    inner.tag = 9191
    button.addSubview(inner)
    NSLayoutConstraint.activate([
      inner.centerXAnchor.constraint(equalTo: button.centerXAnchor),
      inner.centerYAnchor.constraint(equalTo: button.centerYAnchor),
      inner.widthAnchor.constraint(equalToConstant: 62),
      inner.heightAnchor.constraint(equalToConstant: 62),
    ])
    return button
  }

  private func configureModeButton(_ button: UIButton, title: String, action: Selector) {
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setTitle(title, for: .normal)
    button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    button.addTarget(self, action: action, for: .touchUpInside)
  }

  private func requestCameraAccessAndConfigure() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self else { return }
        if granted {
          self.configureSession()
        } else {
          DispatchQueue.main.async {
            self.dismissAndComplete(
              payload: nil,
              error: NSError(
                domain: "turna.status.camera",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Kamera erişimi gerekli."]
              )
            )
          }
        }
      }
    default:
      dismissAndComplete(
        payload: nil,
        error: NSError(
          domain: "turna.status.camera",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Kamera erişimi gerekli."]
        )
      )
    }
  }

  private func configureSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }

      self.session.beginConfiguration()
      self.session.sessionPreset = .high

      do {
        if let videoInput = self.videoInput {
          self.session.removeInput(videoInput)
          self.videoInput = nil
        }
        if let audioInput = self.audioInput {
          self.session.removeInput(audioInput)
          self.audioInput = nil
        }

        guard let videoDevice = self.cameraDevice(position: self.currentPosition) else {
          throw NSError(
            domain: "turna.status.camera",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Kamera bulunamadı."]
          )
        }
        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard self.session.canAddInput(videoInput) else {
          throw NSError(
            domain: "turna.status.camera",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Kamera girdisi eklenemedi."]
          )
        }
        self.session.addInput(videoInput)
        self.videoInput = videoInput

        if !self.session.outputs.contains(where: { $0 === self.photoOutput }),
          self.session.canAddOutput(self.photoOutput)
        {
          self.session.addOutput(self.photoOutput)
        }
        if !self.session.outputs.contains(where: { $0 === self.movieOutput }),
          self.session.canAddOutput(self.movieOutput)
        {
          self.session.addOutput(self.movieOutput)
        }
        self.configureAudioInputIfAuthorized()

        self.session.commitConfiguration()
        self.configuredSession = true
        self.session.startRunning()

        DispatchQueue.main.async {
          self.updateModeUI()
        }
      } catch {
        self.session.commitConfiguration()
        DispatchQueue.main.async {
          self.dismissAndComplete(payload: nil, error: error)
        }
      }
    }
  }

  private func configureAudioInputIfAuthorized() {
    guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
      return
    }
    guard audioInput == nil else { return }
    guard let audioDevice = AVCaptureDevice.default(for: .audio) else { return }
    guard let input = try? AVCaptureDeviceInput(device: audioDevice) else { return }
    guard session.canAddInput(input) else { return }
    session.addInput(input)
    audioInput = input
  }

  private func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
  }

  @objc private func handleClosePressed() {
    if movieOutput.isRecording {
      cancelPendingAfterRecording = true
      movieOutput.stopRecording()
      return
    }
    dismissAndComplete(payload: nil, error: nil)
  }

  @objc private func handleFlashPressed() {
    guard currentPosition == .back else { return }
    currentFlashMode = currentFlashMode == .off ? .on : .off
    if currentMode == .video {
      setTorchEnabled(currentFlashMode == .on)
    }
    updateModeUI()
  }

  @objc private func handleFlipPressed() {
    guard !movieOutput.isRecording else { return }
    currentPosition = currentPosition == .back ? .front : .back
    currentFlashMode = .off
    configureSession()
  }

  @objc private func handlePhotoModePressed() {
    setMode(.photo)
  }

  @objc private func handleVideoModePressed() {
    setMode(.video)
  }

  private func setMode(_ mode: Mode) {
    guard currentMode != mode else { return }
    currentMode = mode
    if mode == .video {
      requestMicrophoneAccessIfNeeded()
    } else {
      setTorchEnabled(false)
    }
    updateModeUI()
  }

  private func requestMicrophoneAccessIfNeeded() {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      sessionQueue.async { [weak self] in
        self?.session.beginConfiguration()
        self?.configureAudioInputIfAuthorized()
        self?.session.commitConfiguration()
      }
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        guard let self, granted else { return }
        self.sessionQueue.async {
          self.session.beginConfiguration()
          self.configureAudioInputIfAuthorized()
          self.session.commitConfiguration()
        }
      }
    default:
      break
    }
  }

  @objc private func handleShutterPressed() {
    switch currentMode {
    case .photo:
      capturePhoto()
    case .video:
      movieOutput.isRecording ? stopVideoRecording() : startVideoRecording()
    }
  }

  private func capturePhoto() {
    let settings = AVCapturePhotoSettings()
    if photoOutput.supportedFlashModes.contains(currentFlashMode) {
      settings.flashMode = currentPosition == .back ? currentFlashMode : .off
    }
    if let connection = photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
      if connection.isVideoMirroringSupported {
        connection.isVideoMirrored = currentPosition == .front
      }
    }
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  private func startVideoRecording() {
    requestMicrophoneAccessIfNeeded()
    let outputUrl = FileManager.default.temporaryDirectory
      .appendingPathComponent("status-video-\(UUID().uuidString)")
      .appendingPathExtension("mov")
    try? FileManager.default.removeItem(at: outputUrl)

    if let connection = movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
      if connection.isVideoMirroringSupported {
        connection.isVideoMirrored = currentPosition == .front
      }
    }
    setTorchEnabled(currentFlashMode == .on)
    movieOutput.startRecording(to: outputUrl, recordingDelegate: self)
    recordingStartedAt = Date()
    startRecordingTimer()
    updateModeUI()
  }

  private func stopVideoRecording() {
    guard movieOutput.isRecording else { return }
    movieOutput.stopRecording()
    invalidateRecordingTimer()
    setTorchEnabled(false)
    updateModeUI()
  }

  private func startRecordingTimer() {
    invalidateRecordingTimer()
    timerLabel.alpha = 1
    timerLabel.text = "00 sn"
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self, let startedAt = self.recordingStartedAt else { return }
      let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
      self.timerLabel.text = String(format: "%02d sn", seconds)
    }
  }

  private func invalidateRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
    recordingStartedAt = nil
    timerLabel.alpha = 0
  }

  private func setTorchEnabled(_ enabled: Bool) {
    guard let device = videoInput?.device, device.hasTorch, currentPosition == .back else { return }
    do {
      try device.lockForConfiguration()
      device.torchMode = enabled ? .on : .off
      device.unlockForConfiguration()
    } catch {
    }
  }

  private func updateModeUI() {
    let accentColor = UIColor(red: 247.0 / 255.0, green: 213.0 / 255.0, blue: 67.0 / 255.0, alpha: 1)
    let normalColor = UIColor.white
    photoModeButton.setTitleColor(currentMode == .photo ? accentColor : normalColor, for: .normal)
    videoModeButton.setTitleColor(currentMode == .video ? accentColor : normalColor, for: .normal)

    let flashImageName: String
    if currentPosition != .back {
      flashImageName = "bolt.slash.fill"
      flashButton.alpha = 0.45
      flashButton.isEnabled = false
    } else {
      flashImageName = currentFlashMode == .off ? "bolt.slash.fill" : "bolt.fill"
      flashButton.alpha = 1
      flashButton.isEnabled = true
    }
    flashButton.setImage(UIImage(systemName: flashImageName), for: .normal)

    if let inner = shutterButton.viewWithTag(9191) {
      UIView.animate(withDuration: 0.16) {
        inner.backgroundColor = self.currentMode == .video ? UIColor.systemRed : UIColor.white
        inner.layer.cornerRadius = self.movieOutput.isRecording ? 10 : 31
        inner.bounds.size = self.movieOutput.isRecording ? CGSize(width: 28, height: 28) : CGSize(width: 62, height: 62)
      }
    }
  }

  private func dismissAndComplete(payload: [String: Any]?, error: Error?) {
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.dismissAndComplete(payload: payload, error: error)
      }
      return
    }
    guard !finished else { return }
    finished = true
    invalidateRecordingTimer()
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.session.isRunning {
        self.session.stopRunning()
      }
    }
    if let error {
      print("[turna-mobile] native status camera finish | {error: \(error.localizedDescription)}")
    } else if let payload {
      let type = payload["type"] as? String ?? "unknown"
      print("[turna-mobile] native status camera finish | {type: \(type)}")
    } else {
      print("[turna-mobile] native status camera finish | {cancelled: true}")
    }
    dismiss(animated: true) { [weak self] in
      self?.onFinish?(payload, error)
    }
  }

  private func payload(for url: URL, type: Mode) -> [String: Any] {
    let mimeType: String
    switch type {
    case .photo:
      mimeType = "image/jpeg"
    case .video:
      mimeType = "video/quicktime"
    }
    return [
      "path": url.path,
      "type": type.rawValue,
      "fileName": url.lastPathComponent,
      "mimeType": mimeType,
    ]
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    if let error {
      dismissAndComplete(payload: nil, error: error)
      return
    }
    guard let data = photo.fileDataRepresentation() else {
      dismissAndComplete(
        payload: nil,
        error: NSError(
          domain: "turna.status.camera",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Fotoğraf işlenemedi."]
        )
      )
      return
    }
    let fileUrl = FileManager.default.temporaryDirectory
      .appendingPathComponent("status-photo-\(UUID().uuidString)")
      .appendingPathExtension("jpg")
    do {
      try data.write(to: fileUrl, options: .atomic)
      dismissAndComplete(payload: payload(for: fileUrl, type: .photo), error: nil)
    } catch {
      dismissAndComplete(payload: nil, error: error)
    }
  }

  func fileOutput(
    _ output: AVCaptureFileOutput,
    didStartRecordingTo fileURL: URL,
    from connections: [AVCaptureConnection]
  ) {
    DispatchQueue.main.async { [weak self] in
      self?.updateModeUI()
    }
  }

  func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection],
    error: Error?
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.invalidateRecordingTimer()
      self.updateModeUI()
      if let error {
        self.dismissAndComplete(payload: nil, error: error)
        return
      }
      if self.cancelPendingAfterRecording {
        self.cancelPendingAfterRecording = false
        self.dismissAndComplete(payload: nil, error: nil)
        return
      }
      self.dismissAndComplete(payload: self.payload(for: outputFileURL, type: .video), error: nil)
    }
  }
}
