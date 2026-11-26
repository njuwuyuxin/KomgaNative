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
import 'package:yomu_platform/yomu_platform.dart';

Uint8List _fakePng(int width, int height, int tag) {
  final b = ByteData(32)
    ..setUint32(16, width)
    ..setUint32(20, height)
    ..setUint8(24, tag);
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

final class _FakeSolidArchiveBridge implements NativeArchiveBridge {
  _FakeSolidArchiveBridge({this.requiredPassword});

  final String? requiredPassword;
  int windowCallCount = 0;

  final Map<String, Uint8List> _files = <String, Uint8List>{
    'ComicInfo.xml': Uint8List.fromList(
      utf8.encode(
        '<ComicInfo><Series>Solid Seven</Series><Manga>YesAndRightToLeft</Manga></ComicInfo>',
      ),
    ),
    for (var i = 1; i <= 6; i++) '0$i.png': _fakePng(800, 1200, i),
  };

  @override
  Future<NativeArchiveListing> listEntries(
    String filePath, {
    String? password,
  }) async {
    if (requiredPassword != null && password != requiredPassword) {
      throw const NativeArchiveException(
        NativeArchiveErrorKind.invalidPassword,
        'Locked archive',
      );
    }
    return NativeArchiveListing(
      format: NativeArchiveFormat.sevenZip,
      isSolid: true,
      entries: <NativeArchiveEntry>[
        for (final e in _files.entries)
          NativeArchiveEntry(
            entryName: e.key,
            uncompressedSize: e.value.length,
          ),
      ],
    );
  }

  @override
  Future<Uint8List> extractEntry({
    required String filePath,
    required String entryName,
    String? password,
  }) async {
    if (requiredPassword != null && password != requiredPassword) {
      throw const NativeArchiveException(
        NativeArchiveErrorKind.invalidPassword,
      );
    }
    return _files[entryName]!;
  }

  @override
  Future<Map<String, Uint8List>> extractWindow({
    required String filePath,
    required List<String> entryNames,
    String? password,
  }) async {
    windowCallCount++;
    return <String, Uint8List>{
      for (final n in entryNames)
        if (_files.containsKey(n)) n: _files[n]!,
    };
  }

  @override
  Future<void> closeArchive(String filePath) async {}
}

void main() {
  group('LMB-12 CBR / CB7 原生归档导入与固实滑动窗口读取', () {
    test('导入固实 CB7 自动解析 ComicInfo.xml，顺序读 6 页仅触发 1 次窗口批量解压', () async {
      final srcTemp = Directory.systemTemp.createTempSync('yomu_cb7_src_');
      final sandboxTemp = Directory.systemTemp.createTempSync('yomu_cb7_sb_');
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        if (srcTemp.existsSync()) srcTemp.deleteSync(recursive: true);
        if (sandboxTemp.existsSync()) sandboxTemp.deleteSync(recursive: true);
      });

      final bridge = _FakeSolidArchiveBridge();
      final storage = LocalComicsStorage(rootResolver: () async => sandboxTemp);
      final importer = LocalComicImporter(
        db: db,
        storage: storage,
        archiveBridge: bridge,
        coverEncoder: (
          Uint8List raw, {
          required ReadingDirection direction,
        }) async => raw,
      );

      // 7z 魔数头
      final cb7File = File('${srcTemp.path}/SolidSeven Vol.1.cb7')
        ..writeAsBytesSync(<int>[0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 0]);

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(cb7File, name: 'SolidSeven Vol.1.cb7'),
      ]);
      expect(result.importedCount, 1);
      expect(result.failures, isEmpty);

      final series = (await db.queryLocalSeries()).items.single;
      expect(series.title, 'Solid Seven');
      expect(series.readingDirection, ReadingDirection.rightToLeft);

      final bookId = result.importedBookIds.single;
      bridge.windowCallCount = 0;

      final readerRepo = LocalReaderRepository(
        db,
        storage,
        archiveBridge: bridge,
      );
      addTearDown(readerRepo.dispose);

      for (var p = 1; p <= 6; p++) {
        final bytes = await readerRepo.pageImage(bookId, p);
        expect(bytes[24], p);
      }
      expect(bridge.windowCallCount, 1);
    });

    test('加密 RAR4/CBR 导入未解锁返回 encrypted 原因', () async {
      final srcTemp = Directory.systemTemp.createTempSync('yomu_cbr_enc_');
      final sandboxTemp = Directory.systemTemp.createTempSync('yomu_cbr_esb_');
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        if (srcTemp.existsSync()) srcTemp.deleteSync(recursive: true);
        if (sandboxTemp.existsSync()) sandboxTemp.deleteSync(recursive: true);
      });

      final importer = LocalComicImporter(
        db: db,
        storage: LocalComicsStorage(rootResolver: () async => sandboxTemp),
        archiveBridge: _FakeSolidArchiveBridge(requiredPassword: 'pw'),
      );
      // RAR4 魔数头
      final cbrFile = File('${srcTemp.path}/Locked.cbr')
        ..writeAsBytesSync(<int>[0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0]);

      final result = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(cbrFile, name: 'Locked.cbr'),
      ]);
      expect(result.importedCount, 0);
      expect(result.failures.single.reason, ImportFailureReason.encrypted);
    });
  });
}
