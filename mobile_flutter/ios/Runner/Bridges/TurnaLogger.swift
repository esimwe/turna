import Foundation

enum TurnaLogLevel: String {
  case debug = "debug"
  case info = "info"
  case warning = "warn"
  case error = "error"
}

enum TurnaLogger {
  private static let breadcrumbLimit = 120
  private static let queue = DispatchQueue(label: "com.turna.mobile.logger")
  private static let formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  private static var breadcrumbItems: [String] = []

  static func debug(_ scope: String, _ message: String, details: [String: Any] = [:]) {
    log(.debug, scope, message, details: details)
  }

  static func info(_ scope: String, _ message: String, details: [String: Any] = [:]) {
    log(.info, scope, message, details: details)
  }

  static func warning(_ scope: String, _ message: String, details: [String: Any] = [:]) {
    log(.warning, scope, message, details: details)
  }

  static func error(_ scope: String, _ message: String, details: [String: Any] = [:]) {
    log(.error, scope, message, details: details)
  }

  static func breadcrumbs() -> [String] {
    queue.sync {
      breadcrumbItems
    }
  }

  private static func log(
    _ level: TurnaLogLevel,
    _ scope: String,
    _ message: String,
    details: [String: Any]
  ) {
    let line = composeLine(level: level, scope: scope, message: message, details: details)
    queue.sync {
      breadcrumbItems.append(line)
      let overflow = breadcrumbItems.count - breadcrumbLimit
      if overflow > 0 {
        breadcrumbItems.removeFirst(overflow)
      }
    }
    guard shouldEmit(level) else { return }
    NSLog("%@", line)
  }

  private static func shouldEmit(_ level: TurnaLogLevel) -> Bool {
    #if DEBUG
      return true
    #else
      switch level {
      case .warning, .error:
        return true
      case .debug, .info:
        return false
      }
    #endif
  }

  private static func composeLine(
    level: TurnaLogLevel,
    scope: String,
    message: String,
    details: [String: Any]
  ) -> String {
    let timestamp = formatter.string(from: Date())
    let trimmedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedScope = trimmedScope.isEmpty ? "app" : trimmedScope
    let formattedDetails =
      details.isEmpty
      ? ""
      : details
        .sorted { $0.key < $1.key }
        .map { "\($0.key): \(stringify($0.value))" }
        .joined(separator: ", ")
    if formattedDetails.isEmpty {
      return "[turna-native][\(timestamp)][\(level.rawValue)][\(normalizedScope)] \(message)"
    }
    return "[turna-native][\(timestamp)][\(level.rawValue)][\(normalizedScope)] \(message) | {\(formattedDetails)}"
  }

  private static func stringify(_ value: Any) -> String {
    if let value = value as? String {
      return value
    }
    if let value = value as? Bool {
      return value ? "true" : "false"
    }
    if let value = value as? NSNumber {
      return value.stringValue
    }
    return String(describing: value)
  }
}
