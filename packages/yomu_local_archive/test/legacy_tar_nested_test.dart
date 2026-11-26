import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

Uint8List _fakePng(int width, int height) {
  final bytes = Uint8List(32);
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
  final view = ByteData.sublistView(bytes);
  view.setUint32(16, width, Endian.big);
  view.setUint32(20, height, Endian.big);
  return bytes;
}

Uint8List _buildTar(Map<String, List<int>> entries) {
  final out = BytesBuilder();
  for (final e in entries.entries) {
    final header = Uint8List(512);
    final nameBytes = utf8.encode(e.key);
    header.setRange(0, nameBytes.length, nameBytes);
    void writeOctal(int offset, int len, int value) {
      final str = value.toRadixString(8).padLeft(len - 1, '0');
      for (var i = 0; i < str.length; i++) {
        header[offset + i] = str.codeUnitAt(i);
      }
      header[offset + len - 1] = 0;
    }

    writeOctal(100, 8, 0x1A4); // 0644
    writeOctal(108, 8, 0);
    writeOctal(116, 8, 0);
    writeOctal(124, 12, e.value.length);
    writeOctal(136, 12, 0);
    for (var i = 148; i < 156; i++) {
      header[i] = 0x20;
    }
    header[156] = 0x30; // '0' regular file
    final magic = ascii.encode('ustar');
    header.setRange(257, 262, magic);
    header[262] = 0;
    header[263] = 0x30;
    header[264] = 0x30;

    var sum = 0;
    for (final b in header) {
      sum += b;
    }
    writeOctal(148, 7, sum);
    header[155] = 0x20;

    out.add(header);
    out.add(e.value);
    final pad = (512 - (e.value.length % 512)) % 512;
    if (pad > 0) out.add(Uint8List(pad));
  }
  out.add(Uint8List(1024));
  return out.takeBytes();
}

Uint8List _buildZipRaw(
  List<({Uint8List nameBytes, List<int> data, int gpFlag})> entries,
) {
  final out = BytesBuilder();
  final cd = BytesBuilder();

  for (final entry in entries) {
    final offset = out.length;
    final data = Uint8List.fromList(entry.data);
    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, entry.gpFlag, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, entry.nameBytes.length, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(entry.nameBytes)
      ..add(data);

    final cdfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, entry.gpFlag, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, entry.nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    cd
      ..add(cdfh.buffer.asUint8List())
      ..add(entry.nameBytes);
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

void main() {
  group('LMB-06 Shift-JIS / GBK 非 UTF-8 文件名真转码', () {
    test('自动识别 Shift-JIS 假名与漫画汉字路径（不带 UTF-8 标志位）', () async {
      // Shift-JIS: "第1巻/マンガ_01.png"
      // 第(91 E6) 1(31) 巻(8A AA) /(2F) マ(83 7D) ン(83 93) ガ(83 4B) _01.png
      final sjisName = Uint8List.fromList(<int>[
        0x91,
        0xE6,
        0x31,
        0x8A,
        0xAA,
        0x2F,
        0x83,
        0x7D,
        0x83,
        0x93,
        0x83,
        0x4B,
        ...ascii.encode('_01.png'),
      ]);
      final zip = _buildZipRaw(
        <({Uint8List nameBytes, List<int> data, int gpFlag})>[
          (nameBytes: sjisName, data: _fakePng(800, 1200), gpFlag: 0),
        ],
      );

      final reader = await ZipComicReader.open(MemoryByteSource(zip));
      addTearDown(reader.close);
      expect(reader.pages.single.entryName, '第1巻/マンガ_01.png');
    });

    test('自动识别 GBK 中文漫画与分卷路径（不带 UTF-8 标志位）', () async {
      // GBK: "第1卷/迷宫饭_封面.png"
      // 第(B5 DA) 1(31) 卷(BE ED) /(2F) 迷(C3 D4) 宫(B9 AC) 饭(B7 B9) _(5F) 封(B7 E2) 面(C3 E6) .png
      final gbkName = Uint8List.fromList(<int>[
        0xB5,
        0xDA,
        0x31,
        0xBE,
        0xED,
        0x2F,
        0xC3,
        0xD4,
        0xB9,
        0xAC,
        0xB7,
        0xB9,
        0x5F,
        0xB7,
        0xE2,
        0xC3,
        0xE6,
        ...ascii.encode('.png'),
      ]);
      final zip = _buildZipRaw(
        <({Uint8List nameBytes, List<int> data, int gpFlag})>[
          (nameBytes: gbkName, data: _fakePng(800, 1200), gpFlag: 0),
        ],
      );

      final reader = await ZipComicReader.open(MemoryByteSource(zip));
      addTearDown(reader.close);
      expect(reader.pages.single.entryName, '第1卷/迷宫饭_封面.png');
    });
  });

  group('LMB-06 CBT/TAR 容器支持', () {
    test('sniffContainerMagic 识别 ustar，openComicArchive 零解压随机读页并支持 fromIndexedPages', () async {
      final p1 = _fakePng(900, 1300);
      final p2 = _fakePng(1800, 1300);
      final tar = _buildTar(<String, List<int>>{
        'Ch02/001.png': p2,
        'Ch01/001.png': p1,
        'ComicInfo.xml': utf8.encode(
          '<ComicInfo><Series>TAR Manga</Series></ComicInfo>',
        ),
      });

      expect(sniffContainerMagic(tar), ContainerMagic.tar);

      final reader = await openComicArchive(MemoryByteSource(tar));
      addTearDown(reader.close);
      expect(reader, isA<TarComicReader>());
      expect(reader.pages, hasLength(2));
      expect(reader.pages[0].entryName, 'Ch01/001.png');
      expect(reader.pages[0].width, 900);
      expect(reader.pages[1].entryName, 'Ch02/001.png');
      expect(reader.pages[1].width, 1800);
      expect(reader.chapters, const <ArchiveChapter>[
        ArchiveChapter(title: 'Ch01', startPage: 1),
        ArchiveChapter(title: 'Ch02', startPage: 2),
      ]);
      expect(await reader.readPage(2), p2);
      expect(await reader.readPage(1), p1);

      // 索引直开 O(1) 随机读取验证
      final indexed = TarComicReader.fromIndexedPages(
        MemoryByteSource(tar),
        reader.pages,
      );
      addTearDown(indexed.close);
      expect(await indexed.readPage(2), p2);
    });
  });

  group('LMB-06 嵌套合集包检测', () {
    test('inspectNestedZipArchives 识别含多卷子归档且无直接图片的合集 ZIP 并按自然序返回', () async {
      final inner1 = _buildZipRaw(
        <({Uint8List nameBytes, List<int> data, int gpFlag})>[
          (
            nameBytes: Uint8List.fromList(utf8.encode('01.png')),
            data: _fakePng(600, 900),
            gpFlag: 0x0800,
          ),
        ],
      );
      final outer = _buildZipRaw(
        <({Uint8List nameBytes, List<int> data, int gpFlag})>[
          (
            nameBytes: Uint8List.fromList(utf8.encode('Vol.10.cbz')),
            data: inner1,
            gpFlag: 0x0800,
          ),
          (
            nameBytes: Uint8List.fromList(utf8.encode('Vol.2.cbz')),
            data: inner1,
            gpFlag: 0x0800,
          ),
          (
            nameBytes: Uint8List.fromList(utf8.encode('Vol.1.cbt')),
            data: _buildTar(<String, List<int>>{'01.png': _fakePng(600, 900)}),
            gpFlag: 0x0800,
          ),
          (
            nameBytes: Uint8List.fromList(utf8.encode('__MACOSX/._Vol.1.cbz')),
            data: <int>[1, 2],
            gpFlag: 0x0800,
          ),
        ],
      );

      final nested = await inspectNestedZipArchives(MemoryByteSource(outer));
      expect(nested.map((e) => e.name).toList(), <String>[
        'Vol.1.cbt',
        'Vol.2.cbz',
        'Vol.10.cbz',
      ]);
    });
  });
}
