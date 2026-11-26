import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_platform/yomu_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LMB-12 ChannelNativeArchiveBridge', () {
    test('listEntries、extractEntry、extractWindow 与密码异常映射', () async {
      const channel = MethodChannel('yomu/native_archive_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            final args = call.arguments as Map<Object?, Object?>;
            switch (call.method) {
              case 'listEntries':
                if (args['filePath'] == '/locked.cb7' &&
                    args['password'] != 'pw123') {
                  throw PlatformException(
                    code: 'INVALID_PASSWORD',
                    message: 'Wrong password',
                  );
                }
                return <String, Object?>{
                  'format': 'sevenZip',
                  'isSolid': true,
                  'entries': <Map<String, Object?>>[
                    <String, Object?>{
                      'entryName': '01.png',
                      'uncompressedSize': 1024,
                      'isEncrypted': false,
                      'isDirectory': false,
                    },
                    <String, Object?>{
                      'entryName': '02.png',
                      'uncompressedSize': 2048,
                      'isEncrypted': false,
                      'isDirectory': false,
                    },
                  ],
                };
              case 'extractWindow':
                final names = (args['entryNames']! as List<Object?>)
                    .cast<String>();
                return <String, Uint8List>{
                  for (final n in names) n: Uint8List.fromList(<int>[1, 2, 3]),
                };
              case 'extractEntry':
                return Uint8List.fromList(<int>[9, 8, 7]);
              default:
                return null;
            }
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final bridge = ChannelNativeArchiveBridge(channel: channel);
      final listing = await bridge.listEntries('/solid.cb7');
      expect(listing.format, NativeArchiveFormat.sevenZip);
      expect(listing.isSolid, isTrue);
      expect(listing.entries, hasLength(2));

      final batch = await bridge.extractWindow(
        filePath: '/solid.cb7',
        entryNames: const <String>['01.png', '02.png'],
      );
      expect(batch.keys, containsAll(<String>['01.png', '02.png']));

      await expectLater(
        () => bridge.listEntries('/locked.cb7'),
        throwsA(
          isA<NativeArchiveException>().having(
            (e) => e.kind,
            'kind',
            NativeArchiveErrorKind.invalidPassword,
          ),
        ),
      );
      final unlocked = await bridge.listEntries(
        '/locked.cb7',
        password: 'pw123',
      );
      expect(unlocked.entries, hasLength(2));
    });
  });
}
