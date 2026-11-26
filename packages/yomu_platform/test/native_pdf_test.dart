import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_platform/yomu_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LMB-11 ChannelNativePdfBridge', () {
    test(
      'inspect 解析页尺寸与大纲，renderPage 支持标准与高清宽度参数，加密 PDF 抛出 invalidPassword',
      () async {
        const channel = MethodChannel('yomu/native_pdf_test');
        final capturedWidths = <int>[];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (MethodCall call) async {
              final args = call.arguments as Map<Object?, Object?>;
              switch (call.method) {
                case 'inspect':
                  if (args['filePath'] == '/locked.pdf' &&
                      args['password'] != 'secret') {
                    throw PlatformException(
                      code: 'INVALID_PASSWORD',
                      message: 'Password required',
                    );
                  }
                  return <String, Object?>{
                    'pageCount': 2,
                    'title': 'Artbook Vol.1',
                    'author': 'Artist',
                    'pages': <Map<String, Object?>>[
                      <String, Object?>{
                        'pageNumber': 1,
                        'width': 600,
                        'height': 900,
                      },
                      <String, Object?>{
                        'pageNumber': 2,
                        'width': 1200,
                        'height': 900,
                      },
                    ],
                    'outline': <Map<String, Object?>>[
                      <String, Object?>{'title': 'Cover', 'startPage': 1},
                      <String, Object?>{'title': 'Spread', 'startPage': 2},
                    ],
                  };
                case 'renderPage':
                  capturedWidths.add(args['targetWidthPx']! as int);
                  return Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]);
                case 'closeDocument':
                  return null;
                default:
                  return null;
              }
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        final bridge = ChannelNativePdfBridge(channel: channel);
        final info = await bridge.inspect('/comic.pdf');
        expect(info.pageCount, 2);
        expect(info.title, 'Artbook Vol.1');
        expect(info.pages[1].widthPt, 1200);
        expect(info.outline, hasLength(2));
        expect(info.outline[1].title, 'Spread');

        // 标准渲染与缩放高清重绘（上限夹紧到 3200）
        await bridge.renderPage(
          filePath: '/comic.pdf',
          pageNumber: 1,
          targetWidthPx: 1600,
        );
        await bridge.renderPage(
          filePath: '/comic.pdf',
          pageNumber: 1,
          targetWidthPx: 5000,
        );
        expect(capturedWidths, <int>[1600, 3200]);

        // 加密 PDF 无密码抛出 invalidPassword，带正确密码放行
        await expectLater(
          () => bridge.inspect('/locked.pdf'),
          throwsA(
            isA<PdfPlatformException>().having(
              (e) => e.kind,
              'kind',
              PdfOpenErrorKind.invalidPassword,
            ),
          ),
        );
        final unlocked = await bridge.inspect(
          '/locked.pdf',
          password: 'secret',
        );
        expect(unlocked.pageCount, 2);

        await bridge.closeDocument('/comic.pdf');
      },
    );
  });
}
