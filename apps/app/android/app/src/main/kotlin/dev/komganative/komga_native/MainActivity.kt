package dev.komganative.komga_native

import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 屏幕常亮 + 音量键翻页 + 申请高刷新率。
 *
 * 用 Window flag 而不是第三方插件：需求就是一个 flag，加插件只会多一层原生构建面。
 * 通道名与 `packages/komga_platform/lib/src/wakelock.dart`、
 * `hardware_keys.dart` 对应；`eink` 方法按厂商/型号做一次保守探测（UI-P3-14）。
 *
 * 音量键：ACTION_DOWN 时通过同一通道发给 Dart，并**消费事件**（返回 true），
 * 否则按音量键会调系统音量。只在阅读器激活期间生效（Dart 侧
 * `HardwareKeys.setActive`），退出阅读器后音量键立刻交还系统。
 */
class MainActivity : FlutterActivity() {
    private var deviceChannel: MethodChannel? = null

    /** 只有阅读器在前台时才消费音量键（由 Dart 侧 setActive 切换）。 */
    private var volumeKeysEnabled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    /**
     * 主动申请设备支持的最高刷新率。
     *
     * 不申请时，不少 ROM（小米/OPPO/一加/vivo 等）会把 Flutter 的 SurfaceView 限制在 60Hz，
     * 120Hz 屏上滑动明显不如其它应用顺（真机上撞到过：手动在系统设置里给本应用开 120Hz 后立刻顺滑）。
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
        // 即使当前已是最高档也照样声明：不声明的话系统空闲时仍可能把本应用降回 60Hz。
        val params = window.attributes
        params.preferredDisplayModeId = best.modeId
        // 部分 ROM 只认 preferredRefreshRate，两者一起设。
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
                // 握手：Dart 侧在订阅音量键流时调用一次，用来判断平台有没有实现。
                // 没有这个分支时 invokeMethod 会抛 MissingPluginException，
                // Dart 侧会降级成空流（这正是 iOS/桌面的期望行为）。
                "volumeKeys" -> result.success(null)
                // 阅读器进入/退出时切换：关闭时音量键完全交还系统。
                "volumeKeysEnabled" -> {
                    volumeKeysEnabled = call.argument<Boolean>("active") ?: false
                    result.success(null)
                }
                // 墨水屏探测：只认厂商/品牌/型号里的已知标记，宁可漏判也不误判
                // （误判会把普通平板的主题切成纯黑白）。
                "eink" -> {
                    val vendor = detectEinkVendor()
                    result.success(
                        mapOf(
                            "isEink" to (vendor != null),
                            "vendor" to (vendor ?: "unknown"),
                        ),
                    )
                }
                else -> result.notImplemented()
            }
        }
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
     *
     * 这些标记来自常见墨水屏设备的 Build 字段；不保证覆盖所有设备，
     * 但误判代价（普通平板被切成黑白）比漏判高，所以只做保守的字符串匹配。
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
    }
}
