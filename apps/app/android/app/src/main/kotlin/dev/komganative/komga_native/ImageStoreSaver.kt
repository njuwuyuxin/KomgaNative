package dev.komganative.komga_native

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import java.io.File
import java.io.IOException

/**
 * 把漫画单页或双页拼接图写入系统默认图片存储位置（`Pictures/Yomu`）。
 *
 * - Android 10+（API 29+）：走分区存储 `MediaStore.Images`，无需任何存储运行时权限，
 *   写入期间置 `IS_PENDING = 1`，写完再揭晓，异常时回滚删除孤儿记录；
 * - Android 7–9（API 24–28，部分老墨水屏阅读器）：写入公开 `Pictures/Yomu` 目录，
 *   并主动触发 `MediaScannerConnection` 刷新系统相册索引。
 */
internal object ImageStoreSaver {
    private const val SUBFOLDER = "Yomu"

    fun save(
        context: Context,
        bytes: ByteArray,
        rawFileName: String,
        mimeType: String,
    ): String {
        val safeName = File(rawFileName).name.ifBlank { "yomu-page.png" }
        val safeMime = mimeType.ifBlank { "image/png" }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(context, bytes, safeName, safeMime)
        } else {
            saveLegacyPublicPictures(context, bytes, safeName, safeMime)
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun saveViaMediaStore(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                "${Environment.DIRECTORY_PICTURES}/$SUBFOLDER",
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("MediaStore.insert returned null")
        try {
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IOException("ContentResolver.openOutputStream returned null")
            val ready = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, ready, null, null)
            return uri.toString()
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacyPublicPictures(
        context: Context,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): String {
        val picturesRoot = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_PICTURES,
        )
        val folder = File(picturesRoot, SUBFOLDER)
        if (!folder.exists() && !folder.mkdirs()) {
            throw IOException("Cannot create directory: ${folder.absolutePath}")
        }
        val target = resolveUniqueFile(folder, fileName)
        target.outputStream().use { stream ->
            stream.write(bytes)
            stream.flush()
        }
        MediaScannerConnection.scanFile(
            context,
            arrayOf(target.absolutePath),
            arrayOf(mimeType),
            null,
        )
        return target.absolutePath
    }

    private fun resolveUniqueFile(folder: File, fileName: String): File {
        var candidate = File(folder, fileName)
        if (!candidate.exists()) return candidate
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val ext = if (dot > 0) fileName.substring(dot) else ""
        var index = 1
        while (candidate.exists()) {
            candidate = File(folder, "$stem ($index)$ext")
            index++
        }
        return candidate
    }
}
