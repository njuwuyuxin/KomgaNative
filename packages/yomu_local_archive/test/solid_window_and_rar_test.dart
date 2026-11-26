import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

Uint8List _buildMinimalRar4({
  required bool solid,
  required bool encrypted,
  Map<String, List<int>> storedFiles = const <String, List<int>>{},
}) {
  final out = BytesBuilder();
  // RAR4 signature
  out.add(const <int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]);

  // Main Archive Header (type 0x73, size 13)
  final mhdFlags = (solid ? 0x0008 : 0) | (encrypted ? 0x0080 : 0);
  final mhd = ByteData(13)
    ..setUint16(0, 0, Endian.little)
    ..setUint8(2, 0x73)
    ..setUint16(3, mhdFlags, Endian.little)
    ..setUint16(5, 13, Endian.little);
  out.add(mhd.buffer.asUint8List());

  for (final e in storedFiles.entries) {
    final nameBytes = utf8.encode(e.key);
    final data = Uint8List.fromList(e.value);
    final headSize = 32 + nameBytes.length;
    final fhd = ByteData(32)
      ..setUint16(0, 0, Endian.little)
      ..setUint8(2, 0x74)
      ..setUint16(3, 0x8200, Endian.little) // LONG_BLOCK | UTF8
      ..setUint16(5, headSize, Endian.little)
      ..setUint32(7, data.length, Endian.little)
      ..setUint32(11, data.length, Endian.little)
      ..setUint8(25, 0x30) // Stored
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(fhd.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);
  }

  return out.takeBytes();
}

void main() {
  group('LMB-12 SolidArchiveWindowCache 滑动窗口优化', () {
    test('顺序翻阅 12 页仅触发 2 次批量窗口解压，并按 LRU 控制缓存上限', () async {
      final names = <String>[for (var i = 1; i <= 12; i++) 'p$i.png'];
      var batchCalls = 0;

      final cache = SolidArchiveWindowCache(
        orderedEntryNames: names,
        windowSize: 6,
        maxCachedPages: 8,
        extractWindow: (List<String> batch) async {
          batchCalls++;
          return <String, Uint8List>{
            for (final n in batch) n: Uint8List.fromList(utf8.encode(n)),
          };
        },
      );

      for (var p = 1; p <= 12; p++) {
        final bytes = await cache.readPage(p);
        expect(utf8.decode(bytes!), 'p$p.png');
      }
      expect(batchCalls, 2);
      expect(cache.cachedPageCount, lessThanOrEqualTo(8));
    });

    test('同窗口并发读取合并为单次批量解压', () async {
      final names = <String>['01.png', '02.png', '03.png', '04.png'];
      var batchCalls = 0;
      final cache = SolidArchiveWindowCache(
        orderedEntryNames: names,
        windowSize: 4,
        extractWindow: (List<String> batch) async {
          batchCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return <String, Uint8List>{
            for (final n in batch) n: Uint8List.fromList(utf8.encode(n)),
          };
        },
      );

      final results = await Future.wait(<Future<Uint8List?>>[
        cache.readPage(1),
        cache.readPage(2),
        cache.readPage(3),
      ]);
      expect(batchCalls, 1);
      expect(results.map((b) => utf8.decode(b!)).toList(), <String>[
        '01.png',
        '02.png',
        '03.png',
      ]);
    });
  });

  group('LMB-12 RAR4 / RAR5 纯 Dart 头嗅探', () {
    test('解析 RAR4 固实/加密标记与无压缩 Stored 条目偏移', () {
      final payload = <int>[1, 2, 3, 4, 5];
      final rar = _buildMinimalRar4(
        solid: true,
        encrypted: false,
        storedFiles: <String, List<int>>{'01.png': payload},
      );
      final probe = inspectRarBytes(rar);
      expect(probe, isNotNull);
      expect(probe!.magic, ContainerMagic.rar4);
      expect(probe.isSolid, isTrue);
      expect(probe.isEncrypted, isFalse);
      expect(probe.storedEntries, hasLength(1));
      expect(probe.storedEntries.single.name, '01.png');
      final extracted = rar.sublist(
        probe.storedEntries.single.dataOffset,
        probe.storedEntries.single.dataOffset + probe.storedEntries.single.size,
      );
      expect(extracted, payload);
    });

    test('识别加密 RAR4 头标记', () {
      final encryptedRar = _buildMinimalRar4(solid: false, encrypted: true);
      final probe = inspectRarBytes(encryptedRar);
      expect(probe?.isEncrypted, isTrue);
    });
  });
}
