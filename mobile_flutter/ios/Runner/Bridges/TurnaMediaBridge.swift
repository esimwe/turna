import AVFoundation
import Flutter
import Foundation
import PDFKit
import Photos
import UIKit
import VisionKit

final class TurnaMediaBridge: NSObject, VNDocumentCameraViewControllerDelegate {
  private let topMostViewControllerProvider: () -> UIViewController?
  private var mediaChannel: FlutterMethodChannel?
  private var statusCameraChannel: FlutterMethodChannel?
  private var pendingStatusCameraResult: FlutterResult?
  private var pendingDocumentScanResult: FlutterResult?
  private var pendingQrScanResult: FlutterResult?
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
      case "shareText":
        guard
          let args = call.arguments as? [String: Any],
          let text = args["text"] as? String,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          result(FlutterError(code: "invalid_args", message: "Paylaşım metni gerekli.", details: nil))
          return
        }
        self.shareText(text: text, result: result)
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
      case "scanQrCode":
        self.presentQrScanner(result: result)
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

  private func shareText(text: String, result: @escaping FlutterResult) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      result(FlutterError(code: "invalid_args", message: "Paylaşım metni gerekli.", details: nil))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let controller = self.topMostViewControllerProvider() else {
        result(FlutterError(code: "missing_view", message: "Paylaşım ekranı açılamadı.", details: nil))
        return
      }
      let activity = UIActivityViewController(activityItems: [normalized], applicationActivities: nil)
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

  private func presentQrScanner(result: @escaping FlutterResult) {
    guard pendingQrScanResult == nil else {
      result(FlutterError(code: "busy", message: "QR tarayıcı zaten açık.", details: nil))
      return
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard let controller = self.topMostViewControllerProvider() else {
        result(FlutterError(code: "missing_view", message: "Tarayıcı açılamadı.", details: nil))
        return
      }

      self.pendingQrScanResult = result
      let scanner = TurnaQrScannerViewController()
      let navigationController = UINavigationController(rootViewController: scanner)
      navigationController.modalPresentationStyle = .fullScreen
      navigationController.isModalInPresentation = true
      scanner.onFinish = { [weak self] value, error in
        guard let self else { return }
        let pending = self.pendingQrScanResult
        self.pendingQrScanResult = nil
        if let error {
          pending?(
            FlutterError(code: "qr_scan_failed", message: error.localizedDescription, details: nil)
          )
        } else {
          pending?(value)
        }
      }
      controller.present(navigationController, animated: true)
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

final class TurnaQrScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onFinish: ((String?, Error?) -> Void)?

  private let captureSession = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "turna.qr.scanner")
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var hasConfiguredSession = false
  private var hasFinished = false

  private let previewContainer = UIView()
  private let headerCard = UIView()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let helperLabel = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .black
    title = "QR kodunu tara"
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "İptal",
      style: .plain,
      target: self,
      action: #selector(cancelTapped)
    )

    previewContainer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(previewContainer)

    headerCard.translatesAutoresizingMaskIntoConstraints = false
    headerCard.backgroundColor = UIColor(white: 1.0, alpha: 0.92)
    headerCard.layer.cornerRadius = 22
    headerCard.layer.cornerCurve = .continuous
    view.addSubview(headerCard)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "web.turna.im veya masaüstü Turna ekranını aç."
    titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
    titleLabel.textColor = .black
    titleLabel.numberOfLines = 0
    titleLabel.textAlignment = .center
    headerCard.addSubview(titleLabel)

    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.text =
      "QR kodu göründüğünde okut. Onay verdiğinde web oturumu otomatik açılır."
    subtitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .regular)
    subtitleLabel.textColor = UIColor(white: 0.34, alpha: 1.0)
    subtitleLabel.numberOfLines = 0
    subtitleLabel.textAlignment = .center
    headerCard.addSubview(subtitleLabel)

    helperLabel.translatesAutoresizingMaskIntoConstraints = false
    helperLabel.text = "QR kodunu çerçevenin içine getir."
    helperLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
    helperLabel.textColor = .white
    helperLabel.textAlignment = .center
    helperLabel.numberOfLines = 0
    view.addSubview(helperLabel)

    NSLayoutConstraint.activate([
      previewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      previewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      previewContainer.topAnchor.constraint(equalTo: view.topAnchor),
      previewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      headerCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      headerCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      headerCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

      titleLabel.topAnchor.constraint(equalTo: headerCard.topAnchor, constant: 18),
      titleLabel.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 18),
      titleLabel.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -18),

      subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
      subtitleLabel.leadingAnchor.constraint(equalTo: headerCard.leadingAnchor, constant: 18),
      subtitleLabel.trailingAnchor.constraint(equalTo: headerCard.trailingAnchor, constant: -18),
      subtitleLabel.bottomAnchor.constraint(equalTo: headerCard.bottomAnchor, constant: -18),

      helperLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      helperLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      helperLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    startIfNeeded()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    stopSession()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = previewContainer.bounds
  }

  @objc private func cancelTapped() {
    finish(value: nil, error: nil)
  }

  private func startIfNeeded() {
    guard !hasConfiguredSession else {
      sessionQueue.async { [weak self] in
        self?.captureSession.startRunning()
      }
      return
    }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureSessionAndStart()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.configureSessionAndStart()
          } else {
            self.finish(
              value: nil,
              error: NSError(
                domain: "turna.qr",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Kamera izni verilmedi."]
              )
            )
          }
        }
      }
    default:
      finish(
        value: nil,
        error: NSError(
          domain: "turna.qr",
          code: -3,
          userInfo: [NSLocalizedDescriptionKey: "Kamera izni verilmedi."]
        )
      )
    }
  }

  private func configureSessionAndStart() {
    guard !hasConfiguredSession else { return }
    hasConfiguredSession = true

    sessionQueue.async { [weak self] in
      guard let self else { return }

      self.captureSession.beginConfiguration()
      self.captureSession.sessionPreset = .high

      guard
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
      else {
        DispatchQueue.main.async {
          self.finish(
            value: nil,
            error: NSError(
              domain: "turna.qr",
              code: -4,
              userInfo: [NSLocalizedDescriptionKey: "Kamera açılamadı."]
            )
          )
        }
        return
      }

      do {
        let input = try AVCaptureDeviceInput(device: device)
        if self.captureSession.canAddInput(input) {
          self.captureSession.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if self.captureSession.canAddOutput(output) {
          self.captureSession.addOutput(output)
          output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
          output.metadataObjectTypes = [.qr]
        }
      } catch {
        DispatchQueue.main.async {
          self.finish(value: nil, error: error)
        }
        return
      }

      self.captureSession.commitConfiguration()

      DispatchQueue.main.async {
        let previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = self.previewContainer.bounds
        self.previewContainer.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
      }

      self.captureSession.startRunning()
    }
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard
      let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
      object.type == .qr,
      let value = object.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else {
      return
    }
    finish(value: value, error: nil)
  }

  private func stopSession() {
    sessionQueue.async { [weak self] in
      guard let self, self.captureSession.isRunning else { return }
      self.captureSession.stopRunning()
    }
  }

  private func finish(value: String?, error: Error?) {
    guard !hasFinished else { return }
    hasFinished = true
    stopSession()
    dismiss(animated: true) { [weak self] in
      self?.onFinish?(value, error)
    }
  }
}
