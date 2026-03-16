import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let appGroupIdentifier = "group.com.turna.chat.shared"
  private let sharePayloadDefaultsKey = "turna.shared_payload"
  private let openURL = URL(string: "turna://share-target")!
  private let statusLabel = UILabel()
  private let activityIndicator = UIActivityIndicatorView(style: .large)
  private var startedProcessing = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    activityIndicator.translatesAutoresizingMaskIntoConstraints = false
    activityIndicator.startAnimating()
    view.addSubview(activityIndicator)

    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    statusLabel.text = "Turna icin hazirlaniyor..."
    statusLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    statusLabel.textColor = .label
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    view.addSubview(statusLabel)

    NSLayoutConstraint.activate([
      activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -18),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 18),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !startedProcessing else { return }
    startedProcessing = true
    processSharedItems()
  }

  private func processSharedItems() {
    guard
      let extensionItems = extensionContext?.inputItems as? [NSExtensionItem]
    else {
      finish()
      return
    }

    let providers = extensionItems.flatMap { $0.attachments ?? [] }
    guard !providers.isEmpty else {
      finish()
      return
    }

    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      finish()
      return
    }

    let shareDirectory = containerURL.appendingPathComponent(
      "IncomingShares",
      isDirectory: true
    )
    try? FileManager.default.createDirectory(
      at: shareDirectory,
      withIntermediateDirectories: true
    )

    let group = DispatchGroup()
    let lock = NSLock()
    var payloadItems = [[String: Any]]()

    for provider in providers {
      guard let typeIdentifier = preferredTypeIdentifier(for: provider) else {
        continue
      }
      group.enter()
      copyProviderToSharedContainer(
        provider: provider,
        typeIdentifier: typeIdentifier,
        shareDirectory: shareDirectory
      ) { item in
        if let item {
          lock.lock()
          payloadItems.append(item)
          lock.unlock()
        }
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      guard !payloadItems.isEmpty else {
        self.finish()
        return
      }
      let defaults = UserDefaults(suiteName: self.appGroupIdentifier)
      defaults?.set(["items": payloadItems], forKey: self.sharePayloadDefaultsKey)
      defaults?.synchronize()
      self.openHostApp()
    }
  }

  private func preferredTypeIdentifier(for provider: NSItemProvider) -> String? {
    let preferredTypes = [
      UTType.image.identifier,
      UTType.movie.identifier,
      UTType.pdf.identifier,
      UTType.data.identifier,
      UTType.item.identifier,
    ]
    for type in preferredTypes where provider.hasItemConformingToTypeIdentifier(type) {
      return type
    }
    return provider.registeredTypeIdentifiers.first
  }

  private func copyProviderToSharedContainer(
    provider: NSItemProvider,
    typeIdentifier: String,
    shareDirectory: URL,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] sourceURL, _ in
      guard let self, let sourceURL else {
        completion(nil)
        return
      }

      let suggestedName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
      let sourceExtension = sourceURL.pathExtension
      let utType = UTType(typeIdentifier)
      let preferredExtension =
        utType?.preferredFilenameExtension ?? (sourceExtension.isEmpty ? nil : sourceExtension)
      let baseName = (suggestedName?.isEmpty == false ? suggestedName! : sourceURL.deletingPathExtension().lastPathComponent)
      let displayFileName = self.fileName(
        baseName: baseName,
        pathExtension: preferredExtension
      )
      let targetFileName = self.uniqueFileName(
        baseName: baseName,
        pathExtension: preferredExtension
      )
      let targetURL = shareDirectory.appendingPathComponent(targetFileName)

      do {
        if FileManager.default.fileExists(atPath: targetURL.path) {
          try FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        let mimeType =
          utType?.preferredMIMEType ??
          Self.guessMimeType(fromPathExtension: targetURL.pathExtension) ??
          "application/octet-stream"
        let values = try targetURL.resourceValues(forKeys: [.fileSizeKey])
        completion([
          "path": targetURL.path,
          "fileName": displayFileName,
          "mimeType": mimeType,
          "sizeBytes": values.fileSize ?? 0,
        ])
      } catch {
        completion(nil)
      }
    }
  }

  private func uniqueFileName(baseName: String, pathExtension: String?) -> String {
    let safeBase = normalizedBaseName(baseName)
    let suffix = UUID().uuidString.prefix(8)
    if let pathExtension, !pathExtension.isEmpty {
      return "\(safeBase)_\(suffix).\(pathExtension)"
    }
    return "\(safeBase)_\(suffix)"
  }

  private func fileName(baseName: String, pathExtension: String?) -> String {
    let safeBase = normalizedBaseName(baseName)
    if let pathExtension, !pathExtension.isEmpty {
      return "\(safeBase).\(pathExtension)"
    }
    return safeBase
  }

  private func normalizedBaseName(_ baseName: String) -> String {
    let normalizedBase =
      baseName.replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: ":", with: "_")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return normalizedBase.isEmpty ? "turna_share" : normalizedBase
  }

  private func openHostApp() {
    let selector = sel_registerName("openURL:")
    var responder: UIResponder? = self
    while let current = responder {
      if current.responds(to: selector) {
        _ = current.perform(selector, with: openURL)
        break
      }
      responder = current.next
    }
    finish()
  }

  private func finish() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }

  private static func guessMimeType(fromPathExtension pathExtension: String) -> String? {
    let normalized = pathExtension.lowercased()
    switch normalized {
    case "jpg", "jpeg":
      return "image/jpeg"
    case "png":
      return "image/png"
    case "heic":
      return "image/heic"
    case "gif":
      return "image/gif"
    case "mp4":
      return "video/mp4"
    case "mov":
      return "video/quicktime"
    case "m4v":
      return "video/x-m4v"
    case "pdf":
      return "application/pdf"
    default:
      return nil
    }
  }
}
