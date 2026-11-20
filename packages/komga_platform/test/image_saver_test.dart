import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komga_platform/komga_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('komganative/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('成功写入时传递字节/文件名/MIME 并返回 ImageSaveSuccess', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          captured = call;
          return <String, Object?>{
            'location': 'content://media/external/images/media/42',
          };
        });

    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final result = await ChannelImageSaver(channel: channel).saveImage(
      bytes,
      fileName: 'komganative-b1-page-1.png',
      mimeType: 'image/png',
    );

    expect(captured?.method, 'saveImage');
    final args = captured?.arguments as Map<Object?, Object?>;
    expect(args['bytes'], bytes);
    expect(args['fileName'], 'komganative-b1-page-1.png');
    expect(args['mimeType'], 'image/png');
    expect(result, isA<ImageSaveSuccess>());
    expect(
      (result as ImageSaveSuccess).location,
      'content://media/external/images/media/42',
    );
  });

  test('权限拒绝、原生 I/O 错误与未实现通道各自映射为密封失败类型', () async {
    final bytes = Uint8List.fromList(<int>[1]);

    // 未注册通道 → MissingPluginException → unsupported。
    final unsupported = await ChannelImageSaver(channel: channel)
        .saveImage(bytes, fileName: 'p.png', mimeType: 'image/png');
    expect(unsupported, isA<ImageSaveFailure>());
    expect(
      (unsupported as ImageSaveFailure).kind,
      ImageSaveFailureKind.unsupported,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'PERMISSION_DENIED', message: 'denied');
        });
    final denied = await ChannelImageSaver(channel: channel)
        .saveImage(bytes, fileName: 'p.png', mimeType: 'image/png');
    expect(
      (denied as ImageSaveFailure).kind,
      ImageSaveFailureKind.permissionDenied,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'IO_ERROR', message: 'disk full');
        });
    final ioErr = await ChannelImageSaver(channel: channel)
        .saveImage(bytes, fileName: 'p.png', mimeType: 'image/png');
    expect((ioErr as ImageSaveFailure).kind, ImageSaveFailureKind.ioError);
    expect(ioErr.message, 'disk full');
  });
}
