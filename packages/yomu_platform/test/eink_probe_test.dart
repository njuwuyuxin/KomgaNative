import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// UI-P3-14：墨水屏探测的 Dart 侧契约。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('komganative/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('原生返回 isEink/vendor 时解析出来', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          expect(call.method, 'eink');
          return <String, Object?>{'isEink': true, 'vendor': 'onyx'};
        });

    final info = await EinkProbe(channel: channel).detect();
    expect(info.isEink, isTrue);
    expect(info.vendor, 'onyx');
  });

  test('没有实现 / 平台异常 / 空结果都退化成 unknown，不抛异常', () async {
    // 没有 handler 等价于 MissingPluginException。
    expect((await EinkProbe(channel: channel).detect()).isEink, isFalse);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'boom');
        });
    expect((await EinkProbe(channel: channel).detect()).isEink, isFalse);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => null);
    expect((await EinkProbe(channel: channel).detect()).isEink, isFalse);
  });
}
