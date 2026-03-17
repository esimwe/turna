import Flutter
import Foundation
import PDFKit
import UIKit

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
