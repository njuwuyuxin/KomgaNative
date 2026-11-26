import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_platform/yomu_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LMB-08 ExternalRootsBridge', () {
    test('localDirectory 支持扫描、.nomedia 创建、.icloud 占位识别与原位区间读取', () async {
      final temp = Directory.systemTemp.createTempSync('yomu_ext_root_');
      addTearDown(() => temp.deleteSync(recursive: true));

      final sub = Directory('${temp.path}/Frieren')..createSync();
      final cbz = File('${sub.path}/Vol.1.cbz')
        ..writeAsBytesSync(Uint8List.fromList(<int>[10, 20, 30, 40, 50, 60]));
      File('${sub.path}/.Vol.2.cbz.icloud').writeAsBytesSync(<int>[1, 2]);
      File('${sub.path}/.hidden.jpg').writeAsBytesSync(<int>[1, 2]);

      final bridge = ChannelExternalRootsBridge();
      final root = MountedExternalRoot(
        id: 'r1',
        displayName: 'Comics',
        uriOrBookmark: temp.path,
        kind: ExternalRootKind.localDirectory,
      );

      expect(await bridge.checkPermission(root), isTrue);
      expect(await bridge.ensureNomedia(root), isTrue);
      expect(File('${temp.path}/.nomedia').existsSync(), isTrue);

      final entries = await bridge.listTree(root);
      final files = entries.where((e) => !e.isDirectory).toList();
      expect(files, hasLength(2));

      final vol1 = files.firstWhere((e) => e.name == 'Vol.1.cbz');
      expect(vol1.relativePath, 'Frieren/Vol.1.cbz');
      expect(vol1.isCloudPlaceholder, isFalse);

      final vol2 = files.firstWhere((e) => e.name == 'Vol.2.cbz');
      expect(vol2.relativePath, 'Frieren/Vol.2.cbz');
      expect(vol2.isCloudPlaceholder, isTrue);

      expect(await bridge.fileLength(cbz.path, root: root), 6);
      expect(
        await bridge.readFileRange(cbz.path, 2, 3, root: root),
        Uint8List.fromList(<int>[30, 40, 50]),
      );
    });

    test('SAF MethodChannel 序列化与随机区间读取', () async {
      const channel = MethodChannel('yomu/external_roots_test');
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            switch (call.method) {
              case 'pickDirectory':
                return <String, Object?>{
                  'uriOrBookmark': 'content://com.android.externalstorage/tree/primary%3AComics',
                  'displayName': 'Comics',
                  'kind': 'androidSaf',
                  'hasNomedia': false,
                };
              case 'checkPermission':
                return true;
              case 'ensureNomedia':
                return true;
              case 'fileLength':
                return 4096;
              case 'readFileRange':
                return Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04]);
              case 'listTree':
                return <Map<String, Object?>>[
                  <String, Object?>{
                    'uri': 'content://doc/1',
                    'relativePath': 'OnePiece/Vol.1.cbz',
                    'name': 'Vol.1.cbz',
                    'isDirectory': false,
                    'sizeBytes': 4096,
                    'lastModifiedMs': 1700000000000,
                    'isCloudPlaceholder': false,
                  },
                ];
              default:
                return null;
            }
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final bridge = ChannelExternalRootsBridge(channel: channel);
      final picked = await bridge.pickDirectory();
      expect(picked, isNotNull);
      expect(picked!.kind, ExternalRootKind.androidSaf);
      expect(picked.displayName, 'Comics');
      expect(await bridge.checkPermission(picked), isTrue);
      expect(await bridge.ensureNomedia(picked), isTrue);

      final tree = await bridge.listTree(picked);
      expect(tree.single.relativePath, 'OnePiece/Vol.1.cbz');
      expect(await bridge.fileLength('content://doc/1', root: picked), 4096);
      expect(
        await bridge.readFileRange('content://doc/1', 0, 4, root: picked),
        Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04]),
      );
    });
  });
}
