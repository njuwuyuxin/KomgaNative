package dev.komganative.komga_native

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * 屏幕常亮 + 音量键翻页 + 申请高刷新率 + 保存页图到系统相册。
 *
 * 用 Window flag / 系统 MediaStore 而不是第三方插件：需求收敛明确，不额外引入原生插件依赖。
 * 通道名与 `packages/komga_platform` 下的抽象一一对应。
 */
class MainActivity : FlutterActivity() {
    private var deviceChannel: MethodChannel? = null
    private var incomingFilesChannel: MethodChannel? = null
    private var externalRootsHandler: SafExternalRootsHandler? = null
    private var nativePdfHandler: NativePdfHandler? = null
    private var dartConsumedInitial = false
    private val pendingIncomingFiles = CopyOnWriteArrayList<Map<String, String>>()
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingStoragePermissionCallback: ((Boolean) -> Unit)? = null

    /** 只有阅读器在前台时才消费音量键（由 Dart 侧 setActive 切换）。 */
    private var volumeKeysEnabled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
        captureIncomingIntent(intent, notifyImmediately = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureIncomingIntent(intent, notifyImmediately = true)
    }

    override fun onDestroy() {
        pendingStoragePermissionCallback = null
        nativePdfHandler?.closeAll()
        ioExecutor.shutdown()
        super.onDestroy()
    }

    /**
     * 主动申请设备支持的最高刷新率。
     *
     * 只在**分辨率与当前模式相同**的模式里挑最高刷新率，避免顺带切换分辨率；
     * 墨水屏通常只有一个模式，这里等于什么都不做。最终是否生效由系统决定（省电模式等仍可降频）。
     */
    private fun requestHighestRefreshRate() {
        @Suppress("DEPRECATION")
        val screen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            this.display
        } else {
            windowManager.defaultDisplay
        } ?: return
        val current = screen.mode
        val best = screen.supportedModes
            .filter {
                it.physicalWidth == current.physicalWidth &&
                    it.physicalHeight == current.physicalHeight
            }
            .maxByOrNull { it.refreshRate } ?: return
        val params = window.attributes
        params.preferredDisplayModeId = best.modeId
        params.preferredRefreshRate = best.refreshRate
        window.attributes = params
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        deviceChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "wakelock" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setKeepScreenOn(enabled)
                    result.success(null)
                }
                "volumeKeys" -> result.success(null)
                "volumeKeysEnabled" -> {
                    volumeKeysEnabled = call.argument<Boolean>("active") ?: false
                    result.success(null)
                }
                "eink" -> {
                    val vendor = detectEinkVendor()
                    result.success(
                        mapOf(
                            "isEink" to (vendor != null),
                            "vendor" to (vendor ?: "unknown"),
                        ),
                    )
                }
                "saveImage" -> handleSaveImage(call, result)
                else -> result.notImplemented()
            }
        }

        val filesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INCOMING_FILES_CHANNEL,
        )
        incomingFilesChannel = filesChannel
        filesChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialFiles" -> {
                    dartConsumedInitial = true
                    val snapshot = ArrayList(pendingIncomingFiles)
                    pendingIncomingFiles.clear()
                    result.success(snapshot)
                }
                else -> result.notImplemented()
            }
        }

        val rootsHandler = SafExternalRootsHandler(this, ioExecutor)
        externalRootsHandler = rootsHandler
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SafExternalRootsHandler.CHANNEL,
        ).setMethodCallHandler { call, result ->
            rootsHandler.handle(call, result)
        }

        val pdfHandler = NativePdfHandler(this, ioExecutor)
        nativePdfHandler = pdfHandler
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativePdfHandler.CHANNEL,
        ).setMethodCallHandler { call, result ->
            pdfHandler.handle(call, result)
        }
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (externalRootsHandler?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun captureIncomingIntent(intent: Intent?, notifyImmediately: Boolean) {
        if (intent == null) return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            }
            else -> null
        }
        if (uri == null) return
        val appContext = applicationContext
        ioExecutor.execute {
            try {
                val displayName = resolveDisplayName(uri) ?: "imported.cbz"
                val safeName = displayName.replace(Regex("[\\\\/:*?\"<>|]"), "_")
                val outDir = File(appContext.cacheDir, "incoming").apply { mkdirs() }
                val destFile = File(outDir, "${System.currentTimeMillis()}_$safeName")
                appContext.contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(destFile).use { output ->
                        input.copyTo(output)
                    }
                } ?: return@execute
                val payload = mapOf("path" to destFile.absolutePath, "name" to displayName)
                runOnUiThread {
                    val ch = incomingFilesChannel
                    if (notifyImmediately && dartConsumedInitial && ch != null) {
                        ch.invokeMethod("incomingFile", payload)
                    } else {
                        pendingIncomingFiles.add(payload)
                    }
                }
            } catch (_: Exception) {
                // 外部无效 URI 静默忽略，不导致主 Activity 崩溃。
            }
        }
    }

    private fun resolveDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") {
            return uri.lastPathSegment
        }
        return try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && cursor.moveToFirst()) cursor.getString(idx) else null
            } ?: uri.lastPathSegment
        } catch (_: Exception) {
            uri.lastPathSegment
        }
    }

    private fun handleSaveImage(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName") ?: "yomu-page.png"
        val mimeType = call.argument<String>("mimeType") ?: "image/png"
        if (bytes == null || bytes.isEmpty()) {
            result.error("IO_ERROR", "Empty image bytes", null)
            return
        }
        ensureLegacyWritePermissionIfNeeded { granted ->
            if (!granted) {
                result.error("PERMISSION_DENIED", "Storage permission denied", null)
                return@ensureLegacyWritePermissionIfNeeded
            }
            val appContext = applicationContext
            ioExecutor.execute {
                try {
                    val location = ImageStoreSaver.save(appContext, bytes, fileName, mimeType)
                    runOnUiThread { result.success(mapOf("location" to location)) }
                } catch (error: Exception) {
                    runOnUiThread {
                        result.error("IO_ERROR", error.message ?: "Failed to save image", null)
                    }
                }
            }
        }
    }

    private fun ensureLegacyWritePermissionIfNeeded(onResult: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            onResult(true)
            return
        }
        val permission = Manifest.permission.WRITE_EXTERNAL_STORAGE
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            onResult(true)
            return
        }
        if (pendingStoragePermissionCallback != null) {
            onResult(false)
            return
        }
        pendingStoragePermissionCallback = onResult
        requestPermissions(arrayOf(permission), REQUEST_WRITE_STORAGE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode == REQUEST_WRITE_STORAGE) {
            val callback = pendingStoragePermissionCallback
            pendingStoragePermissionCallback = null
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            callback?.invoke(granted)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    /**
     * 音量键翻页。
     *
     * 只处理 ACTION_DOWN（长按的重复事件也会来，表现为连续翻页），其它键原样交给
     * super，避免把返回键/键盘事件也吞掉。
     */
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeysEnabled && event.action == KeyEvent.ACTION_DOWN) {
            val direction = when (event.keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> "up"
                KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
                else -> null
            }
            if (direction != null) {
                deviceChannel?.invokeMethod("volumeKey", direction)
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun setKeepScreenOn(enabled: Boolean) {
        if (enabled) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    /**
     * 墨水屏厂商/型号标记。
     */
    private fun detectEinkVendor(): String? {
        val identity = listOf(Build.MANUFACTURER, Build.BRAND, Build.MODEL)
            .joinToString(" ")
            .lowercase()
        val vendors = listOf(
            "onyx" to "onyx",
            "boox" to "onyx",
            "remarkable" to "remarkable",
            "pocketbook" to "pocketbook",
            "kobo" to "kobo",
            "tolino" to "tolino",
            "boyue" to "boyue",
            "likebook" to "boyue",
            "meebook" to "meebook",
            "supernote" to "supernote",
            "hisense" to "hisense",
        )
        return vendors.firstOrNull { identity.contains(it.first) }?.second
    }

    companion object {
        private const val CHANNEL = "komganative/device"
        private const val INCOMING_FILES_CHANNEL = "yomu/incoming_files"
        private const val REQUEST_WRITE_STORAGE = 1042
    }
}
