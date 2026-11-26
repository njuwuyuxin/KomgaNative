import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 测试专用的纯内存 ZIP 字节构造器（支持 Stored / Deflate / 加密位 / 注释 / ZIP64）。
final class TestZipEntrySpec {
  const TestZipEntrySpec({
    required this.name,
    required this.data,
    this.deflate = false,
    this.encrypted = false,
    this.methodOverride,
    this.rawNameBytes,
  });

  final String name;
  final List<int> data;
  final bool deflate;
  final bool encrypted;
  final int? methodOverride;
  final Uint8List? rawNameBytes;
}

Uint8List buildTestZip(
  List<TestZipEntrySpec> specs, {
  String archiveComment = '',
  bool useZip64 = false,
}) {
  final out = BytesBuilder(copy: false);
  final cd = BytesBuilder(copy: false);

  for (final spec in specs) {
    final localOffset = out.length;
    final nameBytes =
        spec.rawNameBytes ?? Uint8List.fromList(utf8.encode(spec.name));
    final isUtf8 = spec.rawNameBytes == null;
    final gpFlag = (isUtf8 ? 0x0800 : 0) | (spec.encrypted ? 0x0001 : 0);
    final method = spec.methodOverride ?? (spec.deflate ? 8 : 0);
    final rawPayload = spec.deflate
        ? ZLibCodec(raw: true).encode(spec.data)
        : spec.data;
    final payload = Uint8List.fromList(rawPayload);

    // Local file header (30 bytes)
    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, useZip64 ? 45 : 20, Endian.little)
      ..setUint16(6, gpFlag, Endian.little)
      ..setUint16(8, method, Endian.little)
      ..setUint32(18, payload.length, Endian.little)
      ..setUint32(22, spec.data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(payload);

    // Central directory header (46 bytes + name + optional zip64 extra)
    final extraBytes = useZip64
        ? _buildZip64Extra(
            uncompressedSize: spec.data.length,
            compressedSize: payload.length,
            localOffset: localOffset,
          )
        : Uint8List(0);

    final cfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, useZip64 ? 45 : 20, Endian.little)
      ..setUint16(6, useZip64 ? 45 : 20, Endian.little)
      ..setUint16(8, gpFlag, Endian.little)
      ..setUint16(10, method, Endian.little)
      ..setUint32(20, useZip64 ? 0xFFFFFFFF : payload.length, Endian.little)
      ..setUint32(24, useZip64 ? 0xFFFFFFFF : spec.data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint16(30, extraBytes.length, Endian.little)
      ..setUint16(32, 0, Endian.little)
      ..setUint32(42, useZip64 ? 0xFFFFFFFF : localOffset, Endian.little);
    cd
      ..add(cfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(extraBytes);
  }

  final cdOffset = out.length;
  final cdBytes = cd.toBytes();
  out.add(cdBytes);

  if (useZip64) {
    final zip64EocdOffset = out.length;
    final rec = ByteData(56)
      ..setUint32(0, 0x06064b50, Endian.little)
      ..setUint64(4, 44, Endian.little)
      ..setUint16(12, 45, Endian.little)
      ..setUint16(14, 45, Endian.little)
      ..setUint64(24, specs.length, Endian.little)
      ..setUint64(32, specs.length, Endian.little)
      ..setUint64(40, cdBytes.length, Endian.little)
      ..setUint64(48, cdOffset, Endian.little);
    final loc = ByteData(20)
      ..setUint32(0, 0x07064b50, Endian.little)
      ..setUint64(8, zip64EocdOffset, Endian.little)
      ..setUint32(16, 1, Endian.little);
    out
      ..add(rec.buffer.asUint8List())
      ..add(loc.buffer.asUint8List());
  }

  final commentBytes = utf8.encode(archiveComment);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, useZip64 ? 0xFFFF : specs.length, Endian.little)
    ..setUint16(10, useZip64 ? 0xFFFF : specs.length, Endian.little)
    ..setUint32(12, useZip64 ? 0xFFFFFFFF : cdBytes.length, Endian.little)
    ..setUint32(16, useZip64 ? 0xFFFFFFFF : cdOffset, Endian.little)
    ..setUint16(20, commentBytes.length, Endian.little);
  out
    ..add(eocd.buffer.asUint8List())
    ..add(commentBytes);

  return out.toBytes();
}

Uint8List _buildZip64Extra({
  required int uncompressedSize,
  required int compressedSize,
  required int localOffset,
}) {
  final extra = ByteData(28)
    ..setUint16(0, 0x0001, Endian.little)
    ..setUint16(2, 24, Endian.little)
    ..setUint64(4, uncompressedSize, Endian.little)
    ..setUint64(12, compressedSize, Endian.little)
    ..setUint64(20, localOffset, Endian.little);
  return extra.buffer.asUint8List();
}

/// 构造最小合法 PNG 头部（精确指定宽高）。
Uint8List fakePngHeader(int width, int height) {
  final b = ByteData(33)
    ..setUint32(8, 13)
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
  bytes.setRange(12, 16, const <int>[0x49, 0x48, 0x44, 0x52]); // 'IHDR'
  return bytes;
}

/// 构造带前置 EXIF APP1 段的 JPEG 头部（覆盖跳过非 SOF 段的逻辑）。
Uint8List fakeJpegWithExifHeader(
  int width,
  int height, {
  int sofMarker = 0xC0,
}) {
  final out = BytesBuilder()
    ..add(const <int>[0xFF, 0xD8]) // SOI
    ..add(const <int>[
      0xFF,
      0xE1,
      0x00,
      0x08,
      0x45,
      0x78,
      0x69,
      0x66,
      0x00,
      0x00,
    ]) // APP1
    ..add(<int>[
      0xFF,
      0xFF, // 填充 FF 测试
      sofMarker,
      0x00,
      0x0B,
      0x08,
      (height >> 8) & 0xFF,
      height & 0xFF,
      (width >> 8) & 0xFF,
      width & 0xFF,
      0x01,
      0x01,
      0x11,
      0x00,
    ]);
  return out.toBytes();
}
