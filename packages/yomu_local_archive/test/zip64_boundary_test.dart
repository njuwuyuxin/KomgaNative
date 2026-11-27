import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

/// 构造包含 ZIP64 EOCD Locator + 标准 EOCD 的恶意 ZIP 尾部，用于测试 64 位偏移溢出与负偏移边界。
Uint8List _buildMaliciousZip64Locator({
  required int zip64EocdOffsetUnsignedLo,
  required int zip64EocdOffsetUnsignedHi,
}) {
  final out = BytesBuilder();
  // 有效 ZIP 起始头魔数（避免被误判成其他容器），补足 56 字节填充区。
  final pad = Uint8List(64);
  pad.setRange(0, 4, const <int>[0x50, 0x4B, 0x03, 0x04]);
  out.add(pad);

  // ZIP64 EOCD Locator (20 bytes)
  final loc = ByteData(20)
    ..setUint32(0, 0x07064b50, Endian.little)
    ..setUint32(4, 0, Endian.little)
    ..setUint32(8, zip64EocdOffsetUnsignedLo, Endian.little)
    ..setUint32(12, zip64EocdOffsetUnsignedHi, Endian.little)
    ..setUint32(16, 1, Endian.little);
  out.add(loc.buffer.asUint8List());

  // Standard EOCD (22 bytes) with cdOffset = 0xFFFFFFFF 触发 ZIP64 路径。
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, 0xFFFFFFFF, Endian.little)
    ..setUint32(16, 0xFFFFFFFF, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

/// 构造 ZIP64 EOCD 记录里 cdOffset / cdSize 溢出的恶意包。
Uint8List _buildMaliciousZip64EocdRecord({
  required int cdSizeLo,
  required int cdSizeHi,
  required int cdOffsetLo,
  required int cdOffsetHi,
}) {
  final out = BytesBuilder();
  // 头部 4 字节 ZIP 魔数
  out.add(const <int>[0x50, 0x4B, 0x03, 0x04]);

  final zip64EocdOffset = out.length;
  final z64Eocd = ByteData(56)
    ..setUint32(0, 0x06064b50, Endian.little)
    ..setUint64(4, 44, Endian.little)
    ..setUint32(40, cdSizeLo, Endian.little)
    ..setUint32(44, cdSizeHi, Endian.little)
    ..setUint32(48, cdOffsetLo, Endian.little)
    ..setUint32(52, cdOffsetHi, Endian.little);
  out.add(z64Eocd.buffer.asUint8List());

  final loc = ByteData(20)
    ..setUint32(0, 0x07064b50, Endian.little)
    ..setUint64(8, zip64EocdOffset, Endian.little)
    ..setUint32(16, 1, Endian.little);
  out.add(loc.buffer.asUint8List());

  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, 0xFFFFFFFF, Endian.little)
    ..setUint32(16, 0xFFFFFFFF, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

/// 构造中央目录 ZIP64 扩展块里 localHeaderOffset 为负数的恶意包。
Uint8List _buildMaliciousZip64ExtraOffset() {
  final out = BytesBuilder();
  out.add(const <int>[0x50, 0x4B, 0x03, 0x04, 0, 0, 0, 0]);

  final nameBytes = utf8.encode('01.png');
  final extra = ByteData(12)
    ..setUint16(0, 0x0001, Endian.little)
    ..setUint16(2, 8, Endian.little)
    ..setUint32(4, 0xFFFFFFFF, Endian.little)
    ..setUint32(8, 0x80000000, Endian.little); // bit 63 = 1 -> signed negative

  final cdOffset = out.length;
  final cdfh = ByteData(46)
    ..setUint32(0, 0x02014b50, Endian.little)
    ..setUint16(4, 45, Endian.little)
    ..setUint16(6, 45, Endian.little)
    ..setUint16(8, 0x0800, Endian.little)
    ..setUint16(10, 0, Endian.little)
    ..setUint32(20, 10, Endian.little)
    ..setUint32(24, 10, Endian.little)
    ..setUint16(28, nameBytes.length, Endian.little)
    ..setUint16(30, extra.lengthInBytes, Endian.little)
    ..setUint32(42, 0xFFFFFFFF, Endian.little);
  final cd = BytesBuilder()
    ..add(cdfh.buffer.asUint8List())
    ..add(nameBytes)
    ..add(extra.buffer.asUint8List());
  final cdBytes = cd.takeBytes();
  out.add(cdBytes);

  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

void main() {
  group('P2-2 ZIP64 负偏移与 64 位整数溢出统一抛出 ArchiveException', () {
    test(
      'ZIP64 EOCD Locator 偏移位 63 置位（负数）抛 ArchiveException 而非 ArgumentError',
      () async {
        final bytes = _buildMaliciousZip64Locator(
          zip64EocdOffsetUnsignedLo: 0xFFFFFFFF,
          zip64EocdOffsetUnsignedHi: 0xFFFFFFFF,
        );

        await expectLater(
          () => readZipCentralDirectory(MemoryByteSource(bytes)),
          throwsA(
            isA<ArchiveException>().having(
              (e) => e.kind,
              'kind',
              ArchiveErrorKind.corruptedArchive,
            ),
          ),
        );
      },
    );

    test(
      'ZIP64 EOCD 记录 cdOffset + cdSize 有符号 64 位回绕溢出抛 ArchiveException',
      () async {
        // cdOffset = 0x7FFFFFFFFFFFFFF0, cdSize = 100 -> 两者均为正但相加溢出为负。
        final bytes = _buildMaliciousZip64EocdRecord(
          cdSizeLo: 100,
          cdSizeHi: 0,
          cdOffsetLo: 0xFFFFFFF0,
          cdOffsetHi: 0x7FFFFFFF,
        );

        await expectLater(
          () => readZipCentralDirectory(MemoryByteSource(bytes)),
          throwsA(
            isA<ArchiveException>().having(
              (e) => e.kind,
              'kind',
              ArchiveErrorKind.corruptedArchive,
            ),
          ),
        );
      },
    );

    test('ZIP64 扩展块条目 localHeaderOffset 溢出成负数抛 ArchiveException', () async {
      final bytes = _buildMaliciousZip64ExtraOffset();

      await expectLater(
        () => readZipCentralDirectory(MemoryByteSource(bytes)),
        throwsA(
          isA<ArchiveException>().having(
            (e) => e.kind,
            'kind',
            ArchiveErrorKind.corruptedArchive,
          ),
        ),
      );
    });
  });
}
