package dev.komganative.komga_native

import android.app.Activity
import com.github.junrar.Archive
import com.github.junrar.exception.CrcErrorException
import com.github.junrar.exception.UnsupportedRarEncryptedException
import com.github.junrar.exception.UnsupportedRarV5Exception
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.apache.commons.compress.PasswordRequiredException
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService

/**
 * Android 原生 CB7 (7z/LZMA2) 与 CBR (RAR4) 解码处理器（LMB-12，ADR 0010）。
 *
 * - 7z / CB7：基于 Apache Commons Compress + Tukaani XZ，支持 LZMA/LZMA2、固实块与密码解密；
 * - RAR4 / CBR：基于 Junrar，支持单趟窗口解压与加密识别；
 * - 单趟 `extractWindow` 一次顺序遍历抽出多页，消除固实包 O(N^2) 解压退化。
 */
class NativeArchiveHandler(
    private val activity: Activity,
    private val ioExecutor: ExecutorService,
) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("filePath")
        val password = call.argument<String>("password")
        when (call.method) {
            "listEntries" -> {
                if (path.isNullOrEmpty()) {
                    result.error("IO_ERROR", "Missing filePath", null)
                    return
                }
                runIo(result) { listEntries(File(path), password) }
            }
            "extractEntry" -> {
                val entryName = call.argument<String>("entryName")
                if (path.isNullOrEmpty() || entryName.isNullOrEmpty()) {
                    result.error("IO_ERROR", "Missing arguments", null)
                    return
                }
                runIo(result) {
                    val map = extractWindow(File(path), listOf(entryName), password)
                    map[entryName] ?: throw IllegalStateException("Entry not found: $entryName")
                }
            }
            "extractWindow" -> {
                val names = call.argument<List<String>>("entryNames") ?: emptyList()
                if (path.isNullOrEmpty()) {
                    result.error("IO_ERROR", "Missing filePath", null)
                    return
                }
                runIo(result) { extractWindow(File(path), names, password) }
            }
            "closeArchive" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun <T> runIo(result: MethodChannel.Result, block: () -> T) {
        ioExecutor.execute {
            try {
                val value = block()
                activity.runOnUiThread { result.success(value) }
            } catch (e: PasswordRequiredException) {
                activity.runOnUiThread {
                    result.error("INVALID_PASSWORD", e.message ?: "Password required", null)
                }
            } catch (e: UnsupportedRarEncryptedException) {
                activity.runOnUiThread {
                    result.error("INVALID_PASSWORD", e.message ?: "Encrypted RAR", null)
                }
            } catch (e: CrcErrorException) {
                activity.runOnUiThread {
                    result.error("INVALID_PASSWORD", e.message ?: "CRC/Password error", null)
                }
            } catch (e: UnsupportedRarV5Exception) {
                activity.runOnUiThread {
                    result.error("UNSUPPORTED", "RAR5 compressed stream is not yet supported by junrar", null)
                }
            } catch (e: Exception) {
                val msg = (e.message ?: "").lowercase()
                val code = when {
                    msg.contains("password") || msg.contains("encrypted") || msg.contains("wrong key") ->
                        "INVALID_PASSWORD"
                    msg.contains("unsupported") -> "UNSUPPORTED"
                    else -> "CORRUPTED"
                }
                activity.runOnUiThread { result.error(code, e.message ?: "Archive error", null) }
            }
        }
    }

    private fun isSevenZip(file: File): Boolean {
        val header = ByteArray(6)
        val read = file.inputStream().use { it.read(header) }
        return read >= 6 &&
            header[0] == 0x37.toByte() &&
            header[1] == 0x7A.toByte() &&
            header[2] == 0xBC.toByte() &&
            header[3] == 0xAF.toByte() &&
            header[4] == 0x27.toByte() &&
            header[5] == 0x1C.toByte()
    }

    private fun openSevenZ(file: File, password: String?): SevenZFile {
        val builder = SevenZFile.builder().setFile(file)
        if (!password.isNullOrEmpty()) {
            builder.setPassword(password.toCharArray())
        }
        return builder.get()
    }

    private fun listEntries(file: File, password: String?): Map<String, Any> {
        if (isSevenZip(file)) {
            openSevenZ(file, password).use { sevenZ ->
                val list = ArrayList<Map<String, Any>>()
                for (entry in sevenZ.entries) {
                    val norm = entry.name.replace('\\', '/')
                    list.add(
                        mapOf(
                            "entryName" to norm,
                            "uncompressedSize" to entry.size,
                            "isEncrypted" to false,
                            "isDirectory" to entry.isDirectory,
                        ),
                    )
                }
                // 7z 默认按固实流处理，启用滑动窗口单趟解压获得最佳吞吐。
                return mapOf("format" to "sevenZip", "isSolid" to true, "entries" to list)
            }
        }

        val archive = if (password.isNullOrEmpty()) Archive(file) else Archive(file, password)
        archive.use { rar ->
            if (rar.isEncrypted && password.isNullOrEmpty()) {
                throw UnsupportedRarEncryptedException()
            }
            val list = ArrayList<Map<String, Any>>()
            var solid = rar.mainHeader?.isSolid == true
            for (fh in rar.fileHeaders) {
                if (fh.isSolid) solid = true
                val rawName = fh.fileName.replace('\\', '/')
                list.add(
                    mapOf(
                        "entryName" to rawName,
                        "uncompressedSize" to fh.fullUnpackSize,
                        "isEncrypted" to fh.isEncrypted,
                        "isDirectory" to fh.isDirectory,
                    ),
                )
            }
            return mapOf("format" to "rar4", "isSolid" to solid, "entries" to list)
        }
    }

    private fun extractWindow(
        file: File,
        entryNames: List<String>,
        password: String?,
    ): Map<String, ByteArray> {
        val wanted = entryNames.toHashSet()
        if (wanted.isEmpty()) return emptyMap()
        val out = LinkedHashMap<String, ByteArray>(wanted.size)

        if (isSevenZip(file)) {
            openSevenZ(file, password).use { sevenZ ->
                while (out.size < wanted.size) {
                    val entry = sevenZ.nextEntry ?: break
                    val norm = entry.name.replace('\\', '/')
                    if (!wanted.contains(norm) || entry.isDirectory) continue
                    val buf = ByteArrayOutputStream(entry.size.toInt().coerceIn(0, 8 * 1024 * 1024))
                    val chunk = ByteArray(16384)
                    while (true) {
                        val n = sevenZ.read(chunk)
                        if (n <= 0) break
                        buf.write(chunk, 0, n)
                    }
                    out[norm] = buf.toByteArray()
                }
            }
            return out
        }

        val archive = if (password.isNullOrEmpty()) Archive(file) else Archive(file, password)
        archive.use { rar ->
            for (fh in rar.fileHeaders) {
                if (out.size >= wanted.size) break
                val norm = fh.fileName.replace('\\', '/')
                if (!wanted.contains(norm) || fh.isDirectory) continue
                val buf = ByteArrayOutputStream()
                rar.extractFile(fh, buf)
                out[norm] = buf.toByteArray()
            }
        }
        return out
    }

    companion object {
        const val CHANNEL = "yomu/native_archive"
    }
}
