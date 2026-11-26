import 'package:flutter/services.dart';

/// 屏幕常亮开关。
///
/// 为什么自己开通道而不是加 `wakelock_plus` 之类的插件：整个需求就是
/// "置一个 Window flag / 一个 UIApplication 属性"，为之引入一个带原生构建的
/// 第三方依赖不划算（见 AGENTS 的依赖规则）。原生侧只加一个方法，
/// 缺实现时静默降级——常亮失败不该影响阅读。
abstract interface class WakeLock {
  Future<void> setEnabled(bool enabled);
}

class ChannelWakeLock implements WakeLock {
  ChannelWakeLock({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('komganative/device');

  final MethodChannel _channel;

  @override
  Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('wakelock', <String, Object?>{
        'enabled': enabled,
      });
    } on MissingPluginException {
      // 桌面/测试/未实现的平台：忽略。iOS 侧还没有实现（无 macOS 环境验证）。
    } on PlatformException {
      // 原生侧失败也只是"屏幕会睡"，不能把阅读打断。
    }
  }
}
