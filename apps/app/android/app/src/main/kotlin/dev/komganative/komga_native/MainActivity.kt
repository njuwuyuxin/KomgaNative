package dev.komganative.komga_native

import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 屏幕常亮 + 音量键翻页。
 *
 * 用 Window flag 而不是第三方插件：需求就是一个 flag，加插件只会多一层原生构建面。
 * 通道名与 `packages/komga_platform/lib/src/wakelock.dart`、
 * `hardware_keys.dart` 对应；`eink` 方法目前未实现（Dart 侧会退化成 EinkInfo.unknown）。
 *
 * 音量键：ACTION_DOWN 时通过同一通道发给 Dart，并**消费事件**（返回 true），
 * 否则按音量键会调系统音量。只在阅读器激活期间生效（Dart 侧
 * `HardwareKeys.setActive`），退出阅读器后音量键立刻交还系统。
 */
class MainActivity : FlutterActivity() {
    private var deviceChannel: MethodChannel? = null

    /** 只有阅读器在前台时才消费音量键（由 Dart 侧 setActive 切换）。 */
    private var volumeKeysEnabled = false

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

    companion object {
        private const val CHANNEL = "komganative/device"
    }
}
