import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

Uint8List _pseudoRandomPng(int totalBytes, int width, int height) {
  final bytes = Uint8List(totalBytes);
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
  ByteData.sublistView(bytes)
    ..setUint32(16, width)
    ..setUint32(20, height);
  // 不可压缩伪随机载荷，确保 Deflate 后仍超过 Isolate 卸载阈值（64 KB）。
  var x = 0x12345678;
  for (var i = 32; i < totalBytes; i++) {
    x = (x * 1664525 + 1013904223) & 0xFFFFFFFF;
    bytes[i] = (x >>> 24) & 0xFF;
  }
  return bytes;
}

Uint8List _buildZip(
  List<({String name, Uint8List payload, int method, Uint8List? passwordBytes})>
  entries,
) {
  final out = BytesBuilder();
  final cd = BytesBuilder();

  for (final e in entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(e.name);
    final crc = computeCrc32(e.payload);
    final compressed = e.method == 8
        ? Uint8List.fromList(ZLibCodec(raw: true).encode(e.payload))
        : e.payload;
    final isEncrypted = e.passwordBytes != null;
    final body = isEncrypted
        ? encryptZipCryptoPayload(
            compressed,
            passwordBytes: e.passwordBytes!,
            checkByte: (crc >> 24) & 0xFF,
          )
        : compressed;
    final gpFlag = 0x0800 | (isEncrypted ? 0x0001 : 0);

    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, gpFlag, Endian.little)
      ..setUint16(8, e.method, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, body.length, Endian.little)
      ..setUint32(22, e.payload.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(body);

    final cdfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, gpFlag, Endian.little)
      ..setUint16(10, e.method, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, body.length, Endian.little)
      ..setUint32(24, e.payload.length, Endian.little)
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
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.takeBytes();
}

Uint8List _buildTar(Map<String, Uint8List> files) {
  final out = BytesBuilder();
  for (final entry in files.entries) {
    final header = Uint8List(512);
    final nameBytes = utf8.encode(entry.key);
    header.setRange(0, nameBytes.length, nameBytes);
    final modeBytes = ascii.encode('0000644\x00');
    header.setRange(100, 100 + modeBytes.length, modeBytes);
    final sizeOctal = entry.value.length.toRadixString(8).padLeft(11, '0');
    header.setRange(124, 135, ascii.encode(sizeOctal));
    header[156] = 0x30; // '0'
    header.setRange(257, 263, ascii.encode('ustar\x00'));
    header.setRange(263, 265, ascii.encode('00'));
    for (var i = 148; i < 156; i++) {
      header[i] = 0x20;
    }
    var sum = 0;
    for (final b in header) {
      sum += b;
    }
    final cksum = sum.toRadixString(8).padLeft(6, '0');
    header.setRange(148, 154, ascii.encode(cksum));
    header[154] = 0;
    header[155] = 0x20;

    out
      ..add(header)
      ..add(entry.value);
    final rem = entry.value.length % 512;
    if (rem != 0) out.add(Uint8List(512 - rem));
  }
  out.add(Uint8List(1024));
  return out.takeBytes();
}

void main() {
  group('P2-2 后台 Isolate 卸载归档解码与扫描', () {
    test('超过阈值的 Deflate 条目在后台 Isolate 正确解压且结果一致', () async {
      final largePage = _pseudoRandomPng(96 * 1024, 1200, 1800);
      final zipBytes = _buildZip(<
        ({String name, Uint8List payload, int method, Uint8List? passwordBytes})
      >[(name: '01.png', payload: largePage, method: 8, passwordBytes: null)]);

      final reader = await ZipComicReader.open(MemoryByteSource(zipBytes));
      addTearDown(reader.close);

      expect(reader.pages, hasLength(1));
      expect(reader.pages.single.width, 1200);
      expect(reader.pages.single.height, 1800);
      final decoded = await reader.readPage(1);
      expect(decoded, largePage);
    });

    test('超过阈值的 ZipCrypto 加密条目在后台 Isolate 正确探测密码并解密解压', () async {
      final largePage = _pseudoRandomPng(72 * 1024, 900, 1400);
      final pwdBytes = Uint8List.fromList(utf8.encode('secret-pass'));
      final zipBytes = _buildZip(<
        ({String name, Uint8List payload, int method, Uint8List? passwordBytes})
      >[
        (
          name: '01.png',
          payload: largePage,
          method: 8,
          passwordBytes: pwdBytes,
        ),
      ]);

      final reader = await ZipComicReader.open(
        MemoryByteSource(zipBytes),
        password: 'secret-pass',
      );
      addTearDown(reader.close);

      final decoded = await reader.readPage(1);
      expect(decoded, largePage);
    });

    test('大型中央目录（>32 KB）在后台 Isolate 正确解析全部条目', () async {
      final tinyPng = _pseudoRandomPng(64, 400, 600);
      final entries =
          <
            ({
              String name,
              Uint8List payload,
              int method,
              Uint8List? passwordBytes,
            })
          >[
            for (var i = 1; i <= 500; i++)
              (
                name:
                    'chapter_volume_directory_${i.toString().padLeft(4, '0')}/page_$i.png',
                payload: tinyPng,
                method: 0,
                passwordBytes: null,
              ),
          ];
      final zipBytes = _buildZip(entries);
      final reader = await ZipComicReader.open(
        MemoryByteSource(zipBytes),
        sniffDimensions: false,
      );
      addTearDown(reader.close);

      expect(reader.pages, hasLength(500));
      expect(reader.pages.first.entryName, contains('0001'));
      expect(reader.pages.last.entryName, contains('0500'));
    });

    test('大型磁盘 TAR 文件（>256 KB）在后台 Isolate 扫描并正确随机读页', () async {
      final tempDir = Directory.systemTemp.createTempSync('yomu_tar_iso_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final page1 = _pseudoRandomPng(160 * 1024, 1000, 1500);
      final page2 = _pseudoRandomPng(160 * 1024, 1100, 1600);
      final tarFile = File('${tempDir.path}/large.cbt');
      tarFile.writeAsBytesSync(
        _buildTar(<String, Uint8List>{'01.png': page1, '02.png': page2}),
      );

      final reader = await TarComicReader.open(
        await FileByteSource.open(tarFile),
      );
      addTearDown(reader.close);

      expect(reader.pages, hasLength(2));
      expect(reader.pages[0].width, 1000);
      expect(reader.pages[1].width, 1100);
      expect(await reader.readPage(2), page2);
    });
  });
}
