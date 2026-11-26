package dev.komganative.komga_native

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService

/**
 * Android SAF 持久化目录树与零拷贝随机字节读取处理器（LMB-08）。
 *
 * 仅依赖 Android Framework 原生 `DocumentsContract` 与 `ParcelFileDescriptor`，
 * 不引入额外第三方依赖。
 */
class SafExternalRootsHandler(
    private val activity: Activity,
    private val ioExecutor: ExecutorService,
) {
    private var pendingPickResult: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> startPickDirectory(result)
            "listTree" -> runIo(result) {
                val uriStr = call.argument<String>("uriOrBookmark") ?: return@runIo emptyList<Map<String, Any>>()
                listTree(activity.applicationContext, Uri.parse(uriStr))
            }
            "checkPermission" -> {
                val uriStr = call.argument<String>("uriOrBookmark")
                if (uriStr.isNullOrEmpty()) {
                    result.success(false)
                } else {
                    val target = Uri.parse(uriStr)
                    val ok = activity.contentResolver.persistedUriPermissions.any {
                        it.uri == target && it.isReadPermission
                    }
                    result.success(ok)
                }
            }
            "ensureNomedia" -> runIo(result) {
                val uriStr = call.argument<String>("uriOrBookmark") ?: return@runIo false
                ensureNomedia(activity.applicationContext, Uri.parse(uriStr))
            }
            "fileLength" -> runIo(result) {
                val uriStr = call.argument<String>("uri") ?: return@runIo null
                queryFileLength(activity.applicationContext, Uri.parse(uriStr))
            }
            "readFileRange" -> runIo(result) {
                val uriStr = call.argument<String>("uri") ?: return@runIo null
                val offset = (call.argument<Number>("offset") ?: 0).toLong()
                val length = (call.argument<Number>("length") ?: 0).toInt()
                readFileRange(activity.applicationContext, Uri.parse(uriStr), offset, length)
            }
            "triggerCloudDownload" -> result.success(false)
            "releasePermission" -> {
                val uriStr = call.argument<String>("uriOrBookmark")
                if (!uriStr.isNullOrEmpty()) {
                    try {
                        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                        activity.contentResolver.releasePersistableUriPermission(Uri.parse(uriStr), flags)
                    } catch (_: Exception) {
                        // 权限已被系统回收时静默忽略。
                    }
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startPickDirectory(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.success(null)
            return
        }
        pendingPickResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
            )
        }
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQUEST_OPEN_TREE)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_OPEN_TREE) return false
        val pending = pendingPickResult
        pendingPickResult = null
        if (pending == null) return true

        val treeUri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (treeUri == null) {
            pending.success(null)
            return true
        }

        val flags = (data?.flags ?: 0) and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        val takeFlags = if (flags != 0) flags else Intent.FLAG_GRANT_READ_URI_PERMISSION
        try {
            activity.contentResolver.takePersistableUriPermission(treeUri, takeFlags)
        } catch (_: SecurityException) {
            // 仅尝试读权限
            try {
                activity.contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: Exception) {
            }
        }

        val appCtx = activity.applicationContext
        ioExecutor.execute {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val displayName = resolveTreeDisplayName(appCtx, treeUri, docId)
            val hasNomedia = hasDirectChild(appCtx, treeUri, docId, ".nomedia")
            activity.runOnUiThread {
                pending.success(
                    mapOf(
                        "uriOrBookmark" to treeUri.toString(),
                        "displayName" to displayName,
                        "kind" to "androidSaf",
                        "hasNomedia" to hasNomedia,
                    ),
                )
            }
        }
        return true
    }

    private fun <T> runIo(result: MethodChannel.Result, block: () -> T) {
        ioExecutor.execute {
            try {
                val value = block()
                activity.runOnUiThread { result.success(value) }
            } catch (e: Exception) {
                activity.runOnUiThread {
                    result.error("IO_ERROR", e.message ?: "SAF I/O error", null)
                }
            }
        }
    }

    private fun resolveTreeDisplayName(ctx: Context, treeUri: Uri, docId: String): String {
        val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        try {
            ctx.contentResolver.query(
                docUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) {
                    val name = cursor.getString(0)
                    if (!name.isNullOrBlank()) return name
                }
            }
        } catch (_: Exception) {
        }
        return docId.substringAfterLast(':').substringAfterLast('/').ifBlank { "Folder" }
    }

    private fun hasDirectChild(
        ctx: Context,
        treeUri: Uri,
        parentDocId: String,
        targetName: String,
    ): Boolean {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        try {
            ctx.contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (!cursor.isNull(0) && cursor.getString(0) == targetName) {
                        return true
                    }
                }
            }
        } catch (_: Exception) {
        }
        return false
    }

    private fun ensureNomedia(ctx: Context, treeUri: Uri): Boolean {
        val rootDocId = DocumentsContract.getTreeDocumentId(treeUri)
        if (hasDirectChild(ctx, treeUri, rootDocId, ".nomedia")) return true
        return try {
            val rootDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, rootDocId)
            DocumentsContract.createDocument(
                ctx.contentResolver,
                rootDocUri,
                "application/octet-stream",
                ".nomedia",
            ) != null
        } catch (_: Exception) {
            false
        }
    }

    private fun listTree(ctx: Context, treeUri: Uri): List<Map<String, Any>> {
        val rootDocId = DocumentsContract.getTreeDocumentId(treeUri)
        val out = ArrayList<Map<String, Any>>()
        walkChildren(ctx, treeUri, rootDocId, "", out)
        return out
    }

    private fun walkChildren(
        ctx: Context,
        treeUri: Uri,
        parentDocId: String,
        prefix: String,
        out: MutableList<Map<String, Any>>,
    ) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        try {
            ctx.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val docId = cursor.getString(0) ?: continue
                    val name = cursor.getString(1) ?: continue
                    if (name.startsWith(".")) continue
                    val mime = cursor.getString(2) ?: ""
                    val size = if (cursor.isNull(3)) 0L else cursor.getLong(3)
                    val mtime = if (cursor.isNull(4)) 0L else cursor.getLong(4)
                    val isDir = mime == DocumentsContract.Document.MIME_TYPE_DIR
                    val relPath = if (prefix.isEmpty()) name else "$prefix/$name"
                    val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    out.add(
                        mapOf(
                            "uri" to docUri.toString(),
                            "relativePath" to relPath,
                            "name" to name,
                            "isDirectory" to isDir,
                            "sizeBytes" to size,
                            "lastModifiedMs" to mtime,
                            "isCloudPlaceholder" to false,
                        ),
                    )
                    if (isDir) {
                        walkChildren(ctx, treeUri, docId, relPath, out)
                    }
                }
            }
        } catch (_: Exception) {
            // 单个不可读子目录跳过，不阻断整棵树扫描。
        }
    }

    private fun queryFileLength(ctx: Context, uri: Uri): Long? {
        ctx.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
            val statSize = pfd.statSize
            if (statSize >= 0) return statSize
            FileInputStream(pfd.fileDescriptor).use { fis ->
                return fis.channel.size()
            }
        }
        return null
    }

    private fun readFileRange(ctx: Context, uri: Uri, offset: Long, length: Int): ByteArray? {
        if (length <= 0) return ByteArray(0)
        ctx.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
            FileInputStream(pfd.fileDescriptor).use { fis ->
                val channel = fis.channel
                val buf = ByteBuffer.allocate(length)
                var pos = offset
                while (buf.hasRemaining()) {
                    val read = channel.read(buf, pos)
                    if (read <= 0) break
                    pos += read
                }
                val actual = buf.position()
                return if (actual == length) buf.array() else buf.array().copyOf(actual)
            }
        }
        return null
    }

    companion object {
        const val CHANNEL = "yomu/external_roots"
        private const val REQUEST_OPEN_TREE = 1043
    }
}
