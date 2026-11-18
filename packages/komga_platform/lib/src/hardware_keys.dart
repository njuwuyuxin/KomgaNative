import 'dart:async';

import 'package:flutter/services.dart';

/// 硬件键触发的翻页意图。
///
/// 只表达"往前/往后"，不表达物理上的上/下：按键到方向的映射在
/// [ChannelHardwareKeys] 里做一次，阅读器只认阅读顺序。
enum PageTurnKey { previous, next }

/// 硬件翻页键抽象。
///
/// 用流而不是回调：阅读器生命周期里订阅/取消一次，键盘事件可能来得比页面
/// 数据早（比如启动瞬间按了音量键），流天然能丢掉没有订阅者的那些事件。
abstract interface class HardwareKeys {
  /// 音量键翻页事件。没有原生实现的平台返回一个**永不发射**的流。
  Stream<PageTurnKey> get volumeKeys;

  /// 只有阅读器在前台时设为 true：原生侧据此决定是否消费音量键。
  ///
  /// 不加这个开关的话，整个 App（列表页、设置、弹窗）都按不了音量——
  /// 那是比"不能翻页"更严重的回归。
  Future<void> setActive(bool active);
}

/// 走 `komganative/device` 通道的音量键实现。
///
/// 原生侧（Android `MainActivity.dispatchKeyEvent`）在 ACTION_DOWN 时
/// `invokeMethod("volumeKey", "up" | "down")`。Dart 侧用
/// `MethodCallHandler → StreamController` 接收（而不是 EventChannel）：
/// 音量键和常亮共用同一个通道，原生侧不需要再多维护一个 EventSink。
///
/// 先发一次 `volumeKeys` 握手：桌面/未实现平台会抛 [MissingPluginException]，
/// 这里静默吞掉并保持空流——没有音量键翻页不该影响阅读。
class ChannelHardwareKeys implements HardwareKeys {
  ChannelHardwareKeys({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('komganative/device');

  final MethodChannel _channel;
  StreamController<PageTurnKey>? _controller;
  bool _attached = false;

  @override
  Stream<PageTurnKey> get volumeKeys {
    final existing = _controller;
    if (existing != null) return existing.stream;
    final controller = StreamController<PageTurnKey>.broadcast();
    controller.onListen = () => unawaited(_attach(controller));
    _controller = controller;
    return controller.stream;
  }

  Future<void> _attach(StreamController<PageTurnKey> controller) async {
    if (_attached) return;
    try {
      await _channel.invokeMethod<void>('volumeKeys');
    } on MissingPluginException {
      // 桌面/测试/iOS：没有实现，保持空流。
      return;
    } on PlatformException {
      // 通道在但握手失败：同样静默降级，不把阅读器打成错误页。
      return;
    }
    if (controller.isClosed) return;
    _attached = true;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'volumeKey') return;
      final key = switch (call.arguments) {
        'up' => PageTurnKey.previous,
        'down' => PageTurnKey.next,
        _ => null,
      };
      if (key != null && !controller.isClosed) controller.add(key);
    });
  }

  @override
  Future<void> setActive(bool active) async {
    try {
      // 必须是 `{"active": bool}`：原生侧用 `call.argument<Boolean>("active")` 取，
      // 传裸 bool 会抛 ClassCastException → 通道报错 → 这里的 catch 吞掉，
      // 表现就是"音量键翻页静默失效，按下去只调系统音量"（真机上踩过）。
      await _channel.invokeMethod<void>('volumeKeysEnabled', <String, Object?>{
        'active': active,
      });
    } on MissingPluginException {
      // 平台没实现：什么都不会发生，音量键由系统处理。
    } on PlatformException {
      // 同上：静默降级。
    }
  }

  /// 释放通道处理器与流（由 provider 的 `ref.onDispose` 调用）。
  void dispose() {
    _attached = false;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }
}
