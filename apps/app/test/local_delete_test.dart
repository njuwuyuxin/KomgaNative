import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_curation_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/local_catalog_mutator_provider.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu_domain/yomu_domain.dart';

Uint8List _tinyCbz(int marker) {
  final png = ByteData(33)
    ..setUint32(8, 13)
    ..setUint32(16, 400)
    ..setUint32(20, 600);
  final pngBytes = png.buffer.asUint8List()
    ..setRange(0, 8, const <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ])
    ..setRange(12, 16, const <int>[0x49, 0x48, 0x44, 0x52])
    ..[32] = marker;

  final name = '01.png'.codeUnits;
  final out = BytesBuilder();
  final lfh = ByteData(30)
    ..setUint32(0, 0x04034b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint32(18, pngBytes.length, Endian.little)
    ..setUint32(22, pngBytes.length, Endian.little)
    ..setUint16(26, name.length, Endian.little);
  out
    ..add(lfh.buffer.asUint8List())
    ..add(name)
    ..add(pngBytes);
  final cdOffset = out.length;
  final cfh = ByteData(46)
    ..setUint32(0, 0x02014b50, Endian.little)
    ..setUint16(4, 20, Endian.little)
    ..setUint16(6, 20, Endian.little)
    ..setUint32(20, pngBytes.length, Endian.little)
    ..setUint32(24, pngBytes.length, Endian.little)
    ..setUint16(28, name.length, Endian.little)
    ..setUint32(42, 0, Endian.little);
  out
    ..add(cfh.buffer.asUint8List())
    ..add(name);
  final cdLen = 46 + name.length;
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, 1, Endian.little)
    ..setUint16(10, 1, Endian.little)
    ..setUint32(12, cdLen, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LMA-09 本地书籍与系列删除（SQLite + 沙盒清理 + 存储统计）', () {
    late Directory srcDir;
    late Directory sandboxDir;
    late ProgressDatabase db;
    late ProviderContainer container;

    setUp(() {
      srcDir = Directory.systemTemp.createTempSync('yomu_del_src_');
      sandboxDir = Directory.systemTemp.createTempSync('yomu_del_sandbox_');
      db = ProgressDatabase(NativeDatabase.memory());
      final storage = LocalComicsStorage(rootResolver: () async => sandboxDir);
      container = ProviderContainer(
        overrides: [
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(storage),
          localComicImporterProvider.overrideWithValue(
            LocalComicImporter(
              db: db,
              storage: storage,
              coverEncoder: (
                raw, {
                required ReadingDirection direction,
              }) async => raw,
            ),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
      if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
      if (sandboxDir.existsSync()) sandboxDir.deleteSync(recursive: true);
    });

    test('单本删除更新系列封面与存储占用；删除最后一本自动清理系列、置顶、收藏集与物理文件', () async {
      final f1 = File('${srcDir.path}/Akira Vol.1.cbz')
        ..writeAsBytesSync(_tinyCbz(1));
      final f2 = File('${srcDir.path}/Akira Vol.2.cbz')
        ..writeAsBytesSync(_tinyCbz(2));
      final f3 = File('${srcDir.path}/Blame Vol.1.cbz')
        ..writeAsBytesSync(_tinyCbz(3));

      final importer = container.read(localComicImporterProvider);
      final batch = await importer.importArchiveFiles(<PickedComicFile>[
        PickedComicFile.fromFile(f1),
        PickedComicFile.fromFile(f2),
        PickedComicFile.fromFile(f3),
      ]);
      expect(batch.importedCount, 3);
      expect(
        (await container.read(localStorageUsageProvider.future)).entries,
        3,
      );

      final akiraSeriesId = batch.importedSeriesIds.first;
      final blameSeriesId = batch.importedSeriesIds.last;
      await db.setPinned(
        serverId: kLocalSourceKey,
        seriesId: akiraSeriesId,
        pinned: true,
      );
      await db.insertLocalCollection(
        id: 'local:col_1',
        name: 'Sci-Fi',
        seriesIds: <String>[akiraSeriesId, blameSeriesId],
      );

      final mutator = container.read(localCatalogMutatorProvider);
      // 先删 Akira Vol.1：系列仍有 Vol.2，不删系列
      final seriesGoneFirst = await mutator.deleteBook(
        batch.importedBookIds[0],
        seriesId: akiraSeriesId,
      );
      expect(seriesGoneFirst, isFalse);
      expect((await db.localSeriesById(akiraSeriesId))?.booksCount, 1);

      // 再删 Akira Vol.2：系列变空自动移除系列与置顶，收藏集自动剔除该系列
      final seriesGoneSecond = await mutator.deleteBook(
        batch.importedBookIds[1],
        seriesId: akiraSeriesId,
      );
      expect(seriesGoneSecond, isTrue);
      expect(await db.localSeriesById(akiraSeriesId), isNull);
      expect(await db.pinnedSeries(kLocalSourceKey), isEmpty);
      expect((await db.localCollectionById('local:col_1'))?.seriesIds, <String>[
        blameSeriesId,
      ]);

      // 整系列删除 Blame：收藏集变空一并移除，沙盒 books/ 下无残留子目录，存储占用归 0
      await mutator.deleteSeries(<String>[blameSeriesId]);
      expect(await db.localCollectionById('local:col_1'), isNull);
      expect(
        Directory('${sandboxDir.path}/books').listSync(),
        isEmpty,
        reason: '沙盒物理漫画目录应完全清理',
      );
      final finalUsage = await container.read(localStorageUsageProvider.future);
      expect(finalUsage.entries, 0);
      expect(finalUsage.bytes, 0);
    });
  });
}
