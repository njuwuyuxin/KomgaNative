import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

import 'support/zip_builder.dart';

void main() {
  group('P0-3 ZIP 解压输出上限与压缩炸弹防护', () {
    test('流式 raw-Deflate 解压在输出超过 maxBytes 时立刻中止，不展开整颗炸弹', () {
      // 4 MiB 全零数据经 raw-Deflate 压缩后仅约 4 KB（~1000x 压缩比）。
      final bombPlain = Uint8List(4 * 1024 * 1024);
      final bombDeflated = Uint8List.fromList(
        ZLibCodec(raw: true).encode(bombPlain),
      );
      expect(bombDeflated.length, lessThan(8 * 1024));

      expect(
        () => inflateRawDeflateBounded(bombDeflated, maxBytes: 16 * 1024),
        throwsA(
          isA<ArchiveException>().having(
            (ArchiveException e) => e.kind,
            'kind',
            ArchiveErrorKind.corruptedArchive,
          ),
        ),
      );
    });

    test('声明 uncompressedSize 与实际解压输出不一致（谎报极小体积）时抛 corruptedArchive', () async {
      final bombPlain = Uint8List(2 * 1024 * 1024);
      final zipBytes = _buildZipWithTamperedDeclaredSize(
        entryName: '01.png',
        realPlain: bombPlain,
        declaredUncompressedSize: 64,
      );
      final source = MemoryByteSource(zipBytes);
      final reader = await ZipComicReader.open(source, sniffDimensions: false);
      addTearDown(reader.close);

      await expectLater(
        () => reader.readPage(1),
        throwsA(
          isA<ArchiveException>().having(
            (ArchiveException e) => e.kind,
            'kind',
            ArchiveErrorKind.corruptedArchive,
          ),
        ),
      );
    });

    test('声明 uncompressedSize 超过硬上限时在读载荷与解压前直接拒绝', () async {
      final tinyPlain = fakePngHeader(800, 1200);
      final zipBytes = _buildZipWithTamperedDeclaredSize(
        entryName: '01.png',
        realPlain: tinyPlain,
        declaredUncompressedSize: kMaxZipEntryUncompressedBytes + 1,
      );
      final source = MemoryByteSource(zipBytes);
      final reader = await ZipComicReader.open(source, sniffDimensions: false);
      addTearDown(reader.close);

      await expectLater(
        () => reader.readPage(1),
        throwsA(
          isA<ArchiveException>().having(
            (ArchiveException e) => e.kind,
            'kind',
            ArchiveErrorKind.corruptedArchive,
          ),
        ),
      );
    });

    test('实际解压字节少于声明 uncompressedSize 时同样拦截', () {
      final plain = Uint8List.fromList(utf8.encode('hello world'));
      final deflated = Uint8List.fromList(ZLibCodec(raw: true).encode(plain));

      expect(
        () => inflateRawDeflateBounded(
          deflated,
          maxBytes: 1024,
          expectedSize: plain.length + 10,
        ),
        throwsA(
          isA<ArchiveException>().having(
            (ArchiveException e) => e.kind,
            'kind',
            ArchiveErrorKind.corruptedArchive,
          ),
        ),
      );
    });

    test('加密 ZIP 条目声明体积超限时直接抛 corruptedArchive', () {
      final pwd = Uint8List.fromList(utf8.encode('secret'));
      final plain = Uint8List.fromList(utf8.encode('tiny'));
      final crc = computeCrc32(plain);
      final deflated = Uint8List.fromList(ZLibCodec(raw: true).encode(plain));
      final encrypted = encryptZipCryptoPayload(
        deflated,
        passwordBytes: pwd,
        checkByte: (crc >> 24) & 0xFF,
      );
      final entry = ZipEntryInfo(
        name: '01.png',
        compressedSize: encrypted.length,
        uncompressedSize: kMaxZipEntryUncompressedBytes + 1,
        localHeaderOffset: 0,
        compressionMethod: 8,
        generalPurposeBitFlag: 0x0001,
        crc32: crc,
      );

      expect(
        () => tryDecryptAndInflateZipEntry(encrypted, entry, pwd),
        throwsA(
          isA<ArchiveException>().having(
            (ArchiveException e) => e.kind,
            'kind',
            ArchiveErrorKind.corruptedArchive,
          ),
        ),
      );
    });

    test('加密 ZIP 谎报极小体积的压缩炸弹：正确密码下也会在超限时中止并拒绝', () {
      final pwd = Uint8List.fromList(utf8.encode('secret'));
      final bombPlain = Uint8List(2 * 1024 * 1024);
      final crc = computeCrc32(bombPlain);
      final deflated = Uint8List.fromList(
        ZLibCodec(raw: true).encode(bombPlain),
      );
      final encrypted = encryptZipCryptoPayload(
        deflated,
        passwordBytes: pwd,
        checkByte: (crc >> 24) & 0xFF,
      );
      final entry = ZipEntryInfo(
        name: '01.png',
        compressedSize: encrypted.length,
        uncompressedSize: 64,
        localHeaderOffset: 0,
        compressionMethod: 8,
        generalPurposeBitFlag: 0x0001,
        crc32: crc,
      );

      final result = tryDecryptAndInflateZipEntry(
        encrypted,
        entry,
        pwd,
        maxUncompressedBytes: 16 * 1024,
      );
      expect(result, isNull);
    });

    test('零字节与截断伪 ZIP 统一抛 ArchiveException（P2-6）', () async {
      await expectLater(
        () => ZipComicReader.open(MemoryByteSource(Uint8List(0))),
        throwsA(isA<ArchiveException>()),
      );
      await expectLater(
        () => ZipComicReader.open(
          MemoryByteSource(Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04])),
        ),
        throwsA(isA<ArchiveException>()),
      );
    });

    test('EOCD 中央目录偏移越出文件末尾时抛 corruptedArchive（P2-6）', () async {
      final out = BytesBuilder()
        ..add(const <int>[0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);
      final eocd = ByteData(22)
        ..setUint32(0, 0x06054b50, Endian.little)
        ..setUint16(8, 1, Endian.little)
        ..setUint16(10, 1, Endian.little)
        ..setUint32(12, 100, Endian.little)
        ..setUint32(16, 999999, Endian.little);
      out.add(eocd.buffer.asUint8List());

      await expectLater(
        () => readZipCentralDirectory(MemoryByteSource(out.takeBytes())),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.corruptedArchive,
          ),
        ),
      );
    });

    test('恶意 TAR 截断载荷不会崩溃，统一抛 ArchiveException（P2-6）', () async {
      final header = Uint8List(512);
      // 文件名 "01.png"
      header.setRange(0, 6, utf8.encode('01.png'));
      // 八进制声明体积 999999 字节，但文件随后立刻截断
      header.setRange(124, 135, utf8.encode('00003641077'));
      header[156] = 0x30; // '0' regular file
      header.setRange(257, 263, utf8.encode('ustar\x00'));
      // 计算有效 tar header checksum（148..155 先填空格）
      for (var i = 148; i < 156; i++) {
        header[i] = 0x20;
      }
      var sum = 0;
      for (final b in header) {
        sum += b;
      }
      final oct = sum.toRadixString(8).padLeft(6, '0');
      header.setRange(148, 154, utf8.encode(oct));
      header[154] = 0;
      header[155] = 0x20;

      await expectLater(() async {
        final reader = await TarComicReader.open(
          MemoryByteSource(header),
          sniffDimensions: false,
        );
        try {
          await reader.readPage(1);
        } finally {
          await reader.close();
        }
      }, throwsA(isA<ArchiveException>()));
    });
  });
}

/// 构造一条真实 Deflate ZIP 条目，但将头部与中央目录里的 `uncompressedSize` 篡改为指定值。
Uint8List _buildZipWithTamperedDeclaredSize({
  required String entryName,
  required Uint8List realPlain,
  required int declaredUncompressedSize,
}) {
  final nameBytes = Uint8List.fromList(utf8.encode(entryName));
  final payload = Uint8List.fromList(ZLibCodec(raw: true).encode(realPlain));

  final out = BytesBuilder(copy: false);
  final lfh = ByteData(30)
    ..setUint32(0, 0x04034b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, 0x0800, Endian.little)
    ..setUint16(8, 8, Endian.little)
    ..setUint32(18, payload.length, Endian.little)
    ..setUint32(22, declaredUncompressedSize, Endian.little)
    ..setUint16(26, nameBytes.length, Endian.little)
    ..setUint16(28, 0, Endian.little);
  out
    ..add(lfh.buffer.asUint8List())
    ..add(nameBytes)
    ..add(payload);

  final cdOffset = out.length;
  final cfh = ByteData(46)
    ..setUint32(0, 0x02014b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, 20, Endian.little)
    ..setUint16(8, 0x0800, Endian.little)
    ..setUint16(10, 8, Endian.little)
    ..setUint32(20, payload.length, Endian.little)
    ..setUint32(24, declaredUncompressedSize, Endian.little)
    ..setUint16(28, nameBytes.length, Endian.little)
    ..setUint16(30, 0, Endian.little)
    ..setUint16(32, 0, Endian.little)
    ..setUint32(42, 0, Endian.little);
  final cd = BytesBuilder(copy: false)
    ..add(cfh.buffer.asUint8List())
    ..add(nameBytes);
  final cdBytes = cd.toBytes();
  out.add(cdBytes);

  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little)
    ..setUint16(20, 0, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}
