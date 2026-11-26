package dev.komganative.komga_native

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.LoadParams
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.LinkedHashMap
import java.util.concurrent.ExecutorService

/**
 * Android 原生 `PdfRenderer` 按需光栅化与句柄缓存处理器（LMB-11）。
 *
 * 零第三方依赖；支持标准清晰度与缩放高清重绘（上限 3200px），
 * Android 15 (API 35)+ 原生支持密码解锁加密 PDF，低版本遇到加密文档准确返回 `INVALID_PASSWORD`。
 */
class NativePdfHandler(
    private val activity: Activity,
    private val ioExecutor: ExecutorService,
) {
    private class OpenPdf(
        val pfd: ParcelFileDescriptor,
        val renderer: PdfRenderer,
        val password: String?,
    )

    private val lock = Any()
    private val openDocs = object : LinkedHashMap<String, OpenPdf>(4, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, OpenPdf>?): Boolean {
            if (size > MAX_OPEN_DOCS && eldest != null) {
                closeQuietly(eldest.value)
                return true
            }
            return false
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "inspect" -> {
                val path = call.argument<String>("filePath")
                val password = call.argument<String>("password")
                if (path.isNullOrEmpty()) {
                    result.error("IO_ERROR", "Missing filePath", null)
                    return
                }
                ioExecutor.execute {
                    try {
                        val info = inspectDocument(path, password)
                        activity.runOnUiThread { result.success(info) }
                    } catch (e: SecurityException) {
                        activity.runOnUiThread {
                            result.error("INVALID_PASSWORD", e.message ?: "Password required", null)
                        }
                    } catch (e: Exception) {
                        activity.runOnUiThread {
                            result.error("CORRUPTED", e.message ?: "Failed to inspect PDF", null)
                        }
                    }
                }
            }
            "renderPage" -> {
                val path = call.argument<String>("filePath")
                val pageNumber = call.argument<Int>("pageNumber") ?: 1
                val targetWidth = (call.argument<Int>("targetWidthPx") ?: 1600).coerceIn(240, 3200)
                val password = call.argument<String>("password")
                if (path.isNullOrEmpty()) {
                    result.error("IO_ERROR", "Missing filePath", null)
                    return
                }
                ioExecutor.execute {
                    try {
                        val pngBytes = renderPageBytes(path, pageNumber, targetWidth, password)
                        activity.runOnUiThread { result.success(pngBytes) }
                    } catch (e: SecurityException) {
                        activity.runOnUiThread {
                            result.error("INVALID_PASSWORD", e.message ?: "Password required", null)
                        }
                    } catch (e: Exception) {
                        activity.runOnUiThread {
                            result.error("IO_ERROR", e.message ?: "Failed to render PDF page", null)
                        }
                    }
                }
            }
            "closeDocument" -> {
                val path = call.argument<String>("filePath")
                ioExecutor.execute {
                    if (!path.isNullOrEmpty()) {
                        synchronized(lock) {
                            openDocs.remove(path)?.let { closeQuietly(it) }
                        }
                    }
                    activity.runOnUiThread { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    fun closeAll() {
        synchronized(lock) {
            for (doc in openDocs.values) {
                closeQuietly(doc)
            }
            openDocs.clear()
        }
    }

    private fun acquire(path: String, password: String?): OpenPdf {
        val existing = openDocs[path]
        if (existing != null && existing.password == password) {
            return existing
        }
        if (existing != null) {
            openDocs.remove(path)
            closeQuietly(existing)
        }
        val file = File(path)
        if (!file.exists()) {
            throw IllegalStateException("PDF file does not exist: $path")
        }
        val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = try {
            if (Build.VERSION.SDK_INT >= 35 && !password.isNullOrEmpty()) {
                val params = LoadParams.Builder().setPassword(password).build()
                PdfRenderer(pfd, params)
            } else {
                PdfRenderer(pfd)
            }
        } catch (e: Exception) {
            try {
                pfd.close()
            } catch (_: Exception) {
            }
            throw e
        }
        val opened = OpenPdf(pfd, renderer, password)
        openDocs[path] = opened
        return opened
    }

    private fun inspectDocument(path: String, password: String?): Map<String, Any> {
        synchronized(lock) {
            val doc = acquire(path, password)
            val count = doc.renderer.pageCount
            val pages = ArrayList<Map<String, Any>>(count)
            for (i in 0 until count) {
                doc.renderer.openPage(i).use { page ->
                    pages.add(
                        mapOf(
                            "pageNumber" to (i + 1),
                            "width" to page.width,
                            "height" to page.height,
                        ),
                    )
                }
            }
            return mapOf(
                "pageCount" to count,
                "pages" to pages,
                "outline" to emptyList<Map<String, Any>>(),
            )
        }
    }

    private fun renderPageBytes(
        path: String,
        pageNumber: Int,
        targetWidthPx: Int,
        password: String?,
    ): ByteArray {
        synchronized(lock) {
            val doc = acquire(path, password)
            val index = (pageNumber - 1).coerceIn(0, (doc.renderer.pageCount - 1).coerceAtLeast(0))
            doc.renderer.openPage(index).use { page ->
                val pageW = page.width.coerceAtLeast(1)
                val pageH = page.height.coerceAtLeast(1)
                val scale = targetWidthPx.toDouble() / pageW.toDouble()
                val renderW = targetWidthPx.coerceIn(1, 3200)
                val renderH = (pageH * scale).toInt().coerceIn(1, 6400)
                val bitmap = Bitmap.createBitmap(renderW, renderH, Bitmap.Config.ARGB_8888)
                try {
                    val canvas = Canvas(bitmap)
                    canvas.drawColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val out = ByteArrayOutputStream()
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                    return out.toByteArray()
                } finally {
                    bitmap.recycle()
                }
            }
        }
    }

    private fun closeQuietly(doc: OpenPdf) {
        try {
            doc.renderer.close()
        } catch (_: Exception) {
        }
        try {
            doc.pfd.close()
        } catch (_: Exception) {
        }
    }

    companion object {
        const val CHANNEL = "yomu/native_pdf"
        private const val MAX_OPEN_DOCS = 2
    }
}
