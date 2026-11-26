import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/comic_file_picker.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comic_importer.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

Uint8List _buildCbz({
  required Map<String, List<int>> entries,
  bool encrypted = false,
}) {
  final out = BytesBuilder();
  final cd = BytesBuilder();
  final gpFlag = 0x0800 | (encrypted ? 0x0001 : 0);

  for (final entry in entries.entries) {
    final offset = out.length;
    final nameBytes = utf8.encode(entry.key);
    final data = Uint8List.fromList(entry.value);

    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, gpFlag, Endian.little)
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    out
      ..add(lfh.buffer.asUint8List())
      ..add(nameBytes)
      ..add(data);

    final cfh = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, gpFlag, Endian.little)
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    cd
      ..add(cfh.buffer.asUint8List())
      ..add(nameBytes);
  }

  final cdOffset = out.length;
  final cdBytes = cd.toBytes();
  out.add(cdBytes);
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}

Uint8List _fakePng(int width, int height) {
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
  bytes.setRange(12, 16, const <int>[0x49, 0x48, 0x44, 0x52]);
  return bytes;
}

void main() {
  group('LocalComicImporter 导入管线测试', () {
    late Directory srcTemp;
    late Directory sandboxTemp;
    late ProgressDatabase db;
    late LocalComicImporter importer;

    setUp(() {
      srcTemp = Directory.systemTemp.createTempSync('yomu_import_src_');
      sandboxTemp = Directory.systemTemp.createTempSync('yomu_import_sandbox_');
      db = ProgressDatabase(NativeDatabase.memory());
      importer = LocalComicImporter(
        db: db,
        storage: LocalComicsStorage(rootResolver: () async => sandboxTemp),
        coverEncoder: (
          Uint8List raw, {
          required ReadingDirection direction,
        }) async => raw,
      );
    });

    tearDown(() async {
      await db.close();
      if (srcTemp.existsSync()) srcTemp.deleteSync(recursive: true);
      if (sandboxTemp.existsSync()) sandboxTemp.deleteSync(recursive: true);
    });

    test('批量导入同名多卷自动归并系列、解析 ComicInfo.xml，遇到加密包隔离报错且不留脏文件', () async {
      final vol1Path = '${srcTemp.path}/Frieren Vol.1.cbz';
      final vol2Path = '${srcTemp.path}/Frieren Vol.2.cbz';
      final badPath = '${srcTemp.path}/Locked.zip';

      await File(vol1Path).writeAsBytes(
        _buildCbz(
          entries: <String, List<int>>{
            'ComicInfo.xml': utf8.encode(
              '<ComicInfo><Series>Frieren</Series><Title>Vol. 1</Title><Number>1</Number><Manga>YesAndRightToLeft</Manga></ComicInfo>',
            ),
            '01.png': _fakePng(800, 1200),
            '02.png': _fakePng(800, 1200),
          },
        ),
      );
      await File(vol2Path).writeAsBytes(
        _buildCbz(entries: <String, List<int>>{'01.png': _fakePng(800, 1200)}),
      );
      await File(badPath).writeAsBytes(
        _buildCbz(
          entries: <String, List<int>>{'01.png': _fakePng(800, 1200)},
          encrypted: true,
        ),
      );

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(File(vol1Path), name: 'Frieren Vol.1.cbz'),
        PickedComicFile.fromFile(File(vol2Path), name: 'Frieren Vol.2.cbz'),
        PickedComicFile.fromFile(File(badPath), name: 'Locked.zip'),
      ]);

      expect(result.importedCount, 2);
      expect(result.importedSeriesIds, hasLength(1), reason: '两卷应归入同一系列');
      expect(result.failures, hasLength(1));
      expect(result.failures.single.fileName, 'Locked.zip');
      expect(result.failures.single.reason, ImportFailureReason.encrypted);

      // 校验沙盒 books/ 下只有 2 个成功的子目录，加密失败包已回滚清理
      final booksDir = Directory('${sandboxTemp.path}/books');
      expect(booksDir.listSync(), hasLength(2));

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.title, 'Frieren');
      expect(series.booksCount, 2);
      expect(series.readingDirection, ReadingDirection.rightToLeft);
    });

    test('importDirectory 支持直接导入图片文件夹', () async {
      final imgDir = Directory('${srcTemp.path}/孤独摇滚 第1话')..createSync();
      await File('${imgDir.path}/002.png').writeAsBytes(_fakePng(900, 1300));
      await File('${imgDir.path}/001.png').writeAsBytes(_fakePng(900, 1300));
      await File('${imgDir.path}/ComicInfo.xml').writeAsString(
        '<ComicInfo><Series>孤独摇滚</Series><Number>1</Number></ComicInfo>',
      );

      final result = await importer.importDirectory(imgDir.path);
      expect(result.importedCount, 1);
      expect(result.failures, isEmpty);

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.title, '孤独摇滚');
      final pages = await db.localPagesForBook(result.importedBookIds.single);
      expect(pages, hasLength(2));
      expect(pages.first.entryName, '001.png');
    });

    test('回归防护：Stream<Uint8List>（file_picker Android/iOS 真实返回流类型）入库不触发 IOSink 协变异常', () async {
      final cbzBytes = _buildCbz(
        entries: <String, List<int>>{'01.png': _fakePng(800, 1200)},
      );
      final picked = PickedComicFile(
        name: 'TypedStream Vol.1.cbz',
        openRead: () => Stream<Uint8List>.value(cbzBytes),
        sizeBytes: cbzBytes.length,
      );

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        picked,
      ]);
      expect(result.importedCount, 1);
      expect(result.failures, isEmpty);
    });

    test('支持导入漫画型 EPUB（按 spine 顺序索引 + OPF 元数据/RTL + 正常读页）', () async {
      final png1 = _fakePng(800, 1200);
      final png2 = _fakePng(800, 1200);
      final epubBytes = _buildCbz(
        entries: <String, List<int>>{
          'mimetype': utf8.encode('application/epub+zip'),
          'META-INF/container.xml': utf8.encode('''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
          'OEBPS/content.opf': utf8.encode('''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Dungeon Meshi Vol.1</dc:title>
    <meta property="belongs-to-collection">Dungeon Meshi</meta>
    <meta property="group-position">1</meta>
  </metadata>
  <manifest>
    <item id="p1" href="text/p1.xhtml" media-type="application/xhtml+xml"/>
    <item id="p2" href="text/p2.xhtml" media-type="application/xhtml+xml"/>
    <item id="i1" href="images/001.png" media-type="image/png"/>
    <item id="i2" href="images/002.png" media-type="image/png"/>
  </manifest>
  <spine page-progression-direction="rtl">
    <itemref idref="p1"/>
    <itemref idref="p2"/>
  </spine>
</package>'''),
          'OEBPS/text/p1.xhtml': utf8.encode(
            '<html><body><img src="../images/001.png"/></body></html>',
          ),
          'OEBPS/text/p2.xhtml': utf8.encode(
            '<html><body><img src="../images/002.png"/></body></html>',
          ),
          'OEBPS/images/001.png': png1,
          'OEBPS/images/002.png': png2,
        },
      );
      final epubFile = File('${srcTemp.path}/dungeon_meshi.epub')
        ..writeAsBytesSync(epubBytes);

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(epubFile, name: 'dungeon_meshi.epub'),
      ]);
      expect(result.importedCount, 1);
      expect(result.failures, isEmpty);

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.title, 'Dungeon Meshi');
      expect(series.readingDirection, ReadingDirection.rightToLeft);

      final bookId = result.importedBookIds.single;
      final readerRepo = LocalReaderRepository(
        db,
        LocalComicsStorage(rootResolver: () async => sandboxTemp),
      );
      addTearDown(readerRepo.dispose);
      final pages = await readerRepo.pages(bookId);
      expect(pages, hasLength(2));
      expect(await readerRepo.pageImage(bookId, 1), png1);
      expect(await readerRepo.pageImage(bookId, 2), png2);
    });

    test('纯文字小说 EPUB 拒绝入库并返回 textOnlyEpub 原因且清理沙盒', () async {
      final prose = List<String>.filled(40, '这是一段足够长的纯文字轻小说正文内容。').join();
      final novelBytes = _buildCbz(
        entries: <String, List<int>>{
          'mimetype': utf8.encode('application/epub+zip'),
          'META-INF/container.xml': utf8.encode('''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>'''),
          'content.opf': utf8.encode('''
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Text Novel</dc:title>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>'''),
          'ch1.xhtml': utf8.encode('<html><body><p>$prose</p></body></html>'),
        },
      );
      final novelFile = File('${srcTemp.path}/novel.epub')
        ..writeAsBytesSync(novelBytes);

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(novelFile, name: 'novel.epub'),
      ]);
      expect(result.importedCount, 0);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.reason, ImportFailureReason.textOnlyEpub);

      final booksDir = Directory('${sandboxTemp.path}/books');
      expect(
        booksDir.existsSync()
            ? booksDir.listSync()
            : const <FileSystemEntity>[],
        isEmpty,
      );
    });

    test('支持导入 CBT/TAR 归档并经 LocalReaderRepository 随机读页', () async {
      Uint8List buildTar(Map<String, List<int>> entries) {
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

          writeOctal(100, 8, 0x1A4);
          writeOctal(108, 8, 0);
          writeOctal(116, 8, 0);
          writeOctal(124, 12, e.value.length);
          writeOctal(136, 12, 0);
          for (var i = 148; i < 156; i++) {
            header[i] = 0x20;
          }
          header[156] = 0x30;
          header.setRange(257, 262, ascii.encode('ustar'));
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

      final p1 = _fakePng(700, 1000);
      final p2 = _fakePng(700, 1000);
      final cbtFile = File('${srcTemp.path}/TarComic Vol.1.cbt')
        ..writeAsBytesSync(
          buildTar(<String, List<int>>{'01.png': p1, '02.png': p2}),
        );

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(cbtFile, name: 'TarComic Vol.1.cbt'),
      ]);
      expect(result.importedCount, 1);
      expect(result.failures, isEmpty);

      final bookId = result.importedBookIds.single;
      final readerRepo = LocalReaderRepository(
        db,
        LocalComicsStorage(rootResolver: () async => sandboxTemp),
      );
      addTearDown(readerRepo.dispose);
      expect(await readerRepo.pages(bookId), hasLength(2));
      expect(await readerRepo.pageImage(bookId, 2), p2);
    });

    test('嵌套 3 卷合集 ZIP 自动拆包归入同一本地系列并清理外层临时包', () async {
      final vol1 = _buildCbz(
        entries: <String, List<int>>{'01.png': _fakePng(800, 1200)},
      );
      final vol2 = _buildCbz(
        entries: <String, List<int>>{'01.png': _fakePng(800, 1200)},
      );
      final vol3 = _buildCbz(
        entries: <String, List<int>>{'01.png': _fakePng(800, 1200)},
      );
      final collectionZip = _buildCbz(
        entries: <String, List<int>>{
          'Vol.3.cbz': vol3,
          'Vol.1.cbz': vol1,
          'Vol.2.cbz': vol2,
        },
      );
      final bundleFile = File('${srcTemp.path}/迷宫饭合集.zip')
        ..writeAsBytesSync(collectionZip);

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(bundleFile, name: '迷宫饭合集.zip'),
      ]);
      expect(result.importedCount, 3);
      expect(result.importedSeriesIds, hasLength(1));
      expect(result.failures, isEmpty);

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.title, '迷宫饭合集');
      expect(series.booksCount, 3);

      // 沙盒 books/ 下只保留拆出的 3 个子卷目录，外层临时合集包已清理
      final booksDir = Directory('${sandboxTemp.path}/books');
      expect(booksDir.listSync(), hasLength(3));
    });
  });
}
