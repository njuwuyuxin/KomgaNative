import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

Uint8List _fakePng(int width, int height) {
  final b = ByteData(32)
    ..setUint32(16, width)
    ..setUint32(20, height);
  final bytes = b.buffer.asUint8List();
  bytes.setRange(0, 8, const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);
  bytes.setRange(12, 16, const <int>[0x49, 0x48, 0x44, 0x52]);
  return bytes;
}

Uint8List _buildEncryptedCbz({
  required Map<String, Uint8List> files,
  required Uint8List passwordBytes,
}) {
  final out = BytesBuilder();
  final cd = BytesBuilder();
  const gpFlag = 0x0801; // UTF-8 | Encrypted

  for (final e in files.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(e.key);
    final crc = computeCrc32(e.value);
    final cipher = encryptZipCryptoPayload(
      e.value,
      passwordBytes: passwordBytes,
      checkByte: (crc >> 24) & 0xFF,
    );

    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, gpFlag, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, cipher.length, Endian.little)
      ..setUint32(22, e.value.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(cipher);

    final cdfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, gpFlag, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, cipher.length, Endian.little)
      ..setUint32(24, e.value.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    cd
      ..add(cdfh.buffer.asUint8List())
      ..add(nameBytes);
  }

  final cdOffset = out.length;
  final cdBytes = cd.takeBytes();
  out.add(cdBytes);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, files.length, Endian.little)
    ..setUint16(10, files.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

void main() {
  group('LMB-13 ZipCrypto 解密与中文密码双编码尝试', () {
    test('ASCII 密码正确解密传统加密 CBZ，错密码与空密码均抛出 encryptedArchive', () async {
      final p1 = _fakePng(800, 1200);
      final p2 = _fakePng(900, 1300);
      final zip = _buildEncryptedCbz(
        files: <String, Uint8List>{'01.png': p1, '02.png': p2},
        passwordBytes: Uint8List.fromList(utf8.encode('manga2026')),
      );

      await expectLater(
        () => ZipComicReader.open(MemoryByteSource(zip)),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.encryptedArchive,
          ),
        ),
      );
      await expectLater(
        () => ZipComicReader.open(MemoryByteSource(zip), password: 'wrong'),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.encryptedArchive,
          ),
        ),
      );

      final reader = await ZipComicReader.open(
        MemoryByteSource(zip),
        password: 'manga2026',
      );
      addTearDown(reader.close);
      expect(reader.pages, hasLength(2));
      expect(reader.pages[0].width, 800);
      expect(await reader.readPage(1), p1);
      expect(await reader.readPage(2), p2);
    });

    test('中文密码（GBK 字节加密的老压缩包）自动通过 UTF-8/GBK 双编码候选成功解锁', () async {
      final p1 = _fakePng(700, 1000);
      final gbkPwdBytes = encodeGbkBytes('迷宫饭');
      expect(gbkPwdBytes, isNotNull);

      final zip = _buildEncryptedCbz(
        files: <String, Uint8List>{'01.png': p1},
        passwordBytes: gbkPwdBytes!,
      );

      // 用户直接输入 Unicode 中文密码 "迷宫饭"，内部自动尝试 UTF-8 失败后命中 GBK 解锁
      final reader = await ZipComicReader.open(
        MemoryByteSource(zip),
        password: '迷宫饭',
      );
      addTearDown(reader.close);
      expect(await reader.readPage(1), p1);
    });
  });
}
