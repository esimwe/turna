package com.turna.chat.bridges

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class TurnaPdfBridge {
    fun getPdfPageCount(
        path: String,
        result: MethodChannel.Result,
    ) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "PDF bulunamadı.", null)
            return
        }

        try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { renderer ->
                    result.success(renderer.pageCount)
                }
            }
        } catch (error: Throwable) {
            result.error("invalid_pdf", error.message, null)
        }
    }

    fun renderPdfPage(
        path: String,
        pageIndex: Int,
        targetWidth: Int,
        result: MethodChannel.Result,
    ) {
        val file = File(path)
        if (!file.exists()) {
            result.error("missing_file", "PDF bulunamadı.", null)
            return
        }

        try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
                PdfRenderer(fd).use { renderer ->
                    if (pageIndex < 0 || pageIndex >= renderer.pageCount) {
                        result.error("invalid_page", "PDF sayfası bulunamadı.", null)
                        return
                    }
                    renderer.openPage(pageIndex).use { page ->
                        val safeWidth = maxOf(1, targetWidth)
                        val scale = safeWidth.toFloat() / page.width.toFloat()
                        val bitmapWidth = safeWidth
                        val bitmapHeight = maxOf(1, (page.height * scale).toInt())
                        val bitmap =
                            Bitmap.createBitmap(
                                bitmapWidth,
                                bitmapHeight,
                                Bitmap.Config.ARGB_8888,
                            )
                        bitmap.eraseColor(android.graphics.Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        val output = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                        bitmap.recycle()
                        result.success(output.toByteArray())
                    }
                }
            }
        } catch (error: Throwable) {
            result.error("render_failed", error.message, null)
        }
    }
}
