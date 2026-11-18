import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_platform/komga_platform.dart';

/// 音量键通道：原生方向 → 阅读顺序的映射，以及没有实现时的静默降级。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('komganative/device');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(
      channel,
      (MethodCall call) async => null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('音量上/下分别映射为上一页/下一页，未知参数忽略', () async {
    final keys = ChannelHardwareKeys(channel: channel);
    final received = <PageTurnKey>[];
    final subscription = keys.volumeKeys.listen(received.add);
    // 订阅后的握手是异步的，放一个事件循环给它完成。
    await Future<void>.delayed(Duration.zero);

    await _send(messenger, 'up');
    await _send(messenger, 'down');
    await _send(messenger, 'mute');
    await Future<void>.delayed(Duration.zero);

    expect(received, <PageTurnKey>[PageTurnKey.previous, PageTurnKey.next]);

    await subscription.cancel();
    keys.dispose();
  });

  test('setActive 发给原生的是 {"active": bool}，不是裸布尔', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return null;
    });

    final keys = ChannelHardwareKeys(channel: channel);
    await keys.setActive(true);
    await keys.setActive(false);
    keys.dispose();

    final payloads = calls
        .where((MethodCall call) => call.method == 'volumeKeysEnabled')
        .toList();
    expect(payloads, hasLength(2));
    // 原生侧是 `call.argument<Boolean>("active")`：传裸 bool 会抛
    // ClassCastException，通道报错后被这里 catch 吞掉，表现就是
    // "音量键翻页静默失效、按下去只调系统音量"（模拟器上踩过）。
    expect(payloads.first.arguments, <String, Object?>{'active': true});
    expect(payloads.last.arguments, <String, Object?>{'active': false});
  });

  test('没有原生实现时安静降级为空流', () async {
    messenger.setMockMethodCallHandler(channel, null);
    final keys = ChannelHardwareKeys(channel: channel);
    final received = <PageTurnKey>[];
    final errors = <Object>[];
    final subscription = keys.volumeKeys.listen(
      received.add,
      onError: errors.add,
    );
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    expect(errors, isEmpty, reason: 'MissingPluginException 不该打给阅读器');

    await subscription.cancel();
    keys.dispose();
  });
}

Future<void> _send(TestDefaultBinaryMessenger messenger, String direction) {
  return messenger.handlePlatformMessage(
    'komganative/device',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('volumeKey', direction),
    ),
    (ByteData? _) {},
  );
}
