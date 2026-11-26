import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_platform/yomu_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('yomu/incoming_files');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('consumeInitialFiles 解析原生暂存文件，未实现平台静默降级为空', () async {
    final noPlugin = ChannelIncomingFiles();
    addTearDown(noPlugin.dispose);
    expect(await noPlugin.consumeInitialFiles(), isEmpty);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'consumeInitialFiles') {
            return <Object?>[
              <String, Object?>{
                'path': '/tmp/incoming/vol1.cbz',
                'name': 'Frieren Vol.1.cbz',
              },
            ];
          }
          return null;
        });

    final client = ChannelIncomingFiles();
    addTearDown(client.dispose);
    final initial = await client.consumeInitialFiles();
    expect(initial, hasLength(1));
    expect(initial.single.path, '/tmp/incoming/vol1.cbz');
    expect(initial.single.name, 'Frieren Vol.1.cbz');
  });
}
