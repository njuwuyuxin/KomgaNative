import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_collections_repository.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_library_repository.dart';
import 'package:yomu/src/data/local/local_read_status_repository.dart';
import 'package:yomu/src/data/local/local_reader_repository.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_sync/yomu_sync.dart';

Uint8List _minimalZipWithTwoPages(Uint8List p1, Uint8List p2) {
  final out = BytesBuilder();
  final cd = BytesBuilder();
  final items = <(String, Uint8List)>[('01.png', p1), ('02.png', p2)];
  for (final (name, data) in items) {
    final offset = out.length;
    final nameBytes = Uint8List.fromList(name.codeUnits);
    final lfh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
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
    ..setUint16(8, items.length, Endian.little)
    ..setUint16(10, items.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, cdOffset, Endian.little);
  out.add(eocd.buffer.asUint8List());
  return out.toBytes();
}

Uint8List _fakePng(int width, int height, int markerByte) {
  final b = ByteData(34)
    ..setUint32(8, 13)
    ..setUint32(16, width)
    ..setUint32(20, height)
    ..setUint8(33, markerByte);
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
  group('Local 四大仓库离线契约测试', () {
    late Directory tempDir;
    late ProgressDatabase db;
    late LocalComicsStorage storage;
    late ProgressSyncService sync;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('yomu_local_repos_');
      db = ProgressDatabase(NativeDatabase.memory());
      storage = LocalComicsStorage(rootResolver: () async => tempDir);
      sync = ProgressSyncService(
        store: DriftProgressStore(db),
        activeScope: () => kLocalSourceKey,
        scopedUpload: (String s, ProgressTarget t) async {
          fail('本地源不应发起远程上传');
        },
      );
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
      'LocalLibrary / LocalReader / LocalReadStatus / LocalCollections 完整闭环',
      () async {
        final page1 = _fakePng(900, 1400, 0xA1);
        final page2 = _fakePng(1800, 1400, 0xB2);
        final cbzBytes = _minimalZipWithTwoPages(page1, page2);

        final cbzFile = await storage.resolveFile('b1/vol1.cbz');
        await cbzFile.parent.create(recursive: true);
        await cbzFile.writeAsBytes(cbzBytes);

        final zipReader = await ZipComicReader.open(
          await FileByteSource.open(cbzFile),
        );
        final indexedPages = zipReader.pages;
        await zipReader.close();

        final inserted = await db.insertImportedLocalBook(
          LocalBookImportDraft(
            bookId: 'local:b1',
            seriesTitle: '迷宫饭',
            bookName: '迷宫饭 Vol.1',
            number: '1',
            numberSort: 1,
            storageKind: 'zip',
            relativePath: 'b1/vol1.cbz',
            sizeBytes: cbzBytes.length,
            pages: indexedPages,
          ),
          generateSeriesId: () => 'local:s1',
        );

        final libRepo = LocalLibraryRepository(db, storage);
        final readerRepo = LocalReaderRepository(db, storage);
        addTearDown(readerRepo.dispose);
        final statusRepo = LocalReadStatusRepository(db, sync);
        final colRepo = LocalCollectionsRepository(db);

        expect(await libRepo.libraries(), isEmpty);
        final shelf = await libRepo.series();
        expect(shelf.items, hasLength(1));
        expect(shelf.items.single.title, '迷宫饭');

        // 无独立缩略图文件时自动回退提取第 1 页作封面
        final cover = await libRepo.seriesCover(inserted.seriesId);
        expect(cover, page1);

        // 阅读器并发拉取同一页合并为同一份 Uint8List 引用
        final pagesInfo = await readerRepo.pages('local:b1');
        expect(pagesInfo, hasLength(2));
        expect(pagesInfo[1].width, 1800);

        final concurrent = await Future.wait<Uint8List>(<Future<Uint8List>>[
          readerRepo.pageImage('local:b1', 2),
          readerRepo.pageImage('local:b1', 2),
        ]);
        expect(identical(concurrent[0], concurrent[1]), isTrue);
        expect(concurrent[0], page2);
        expect(readerRepo.cachedPageImage('local:b1', 2), isNotNull);

        // 整系列标为已读 / 未读
        await statusRepo.setSeriesRead(inserted.seriesId, read: true);
        expect(
          (await libRepo.seriesById(inserted.seriesId))?.booksReadCount,
          1,
        );
        await statusRepo.setBookRead('local:b1', read: false, pagesCount: 2);
        expect((await libRepo.book('local:b1'))?.isUnread, isTrue);

        // 本地收藏集与阅读列表闭环
        final col = await colRepo.createCollection(
          name: '最爱',
          seriesIds: <String>[inserted.seriesId],
        );
        expect((await colRepo.collections()).items, hasLength(1));
        expect(
          (await colRepo.collectionSeries(col.id)).items.single.id,
          inserted.seriesId,
        );

        final rl = await colRepo.createReadList(
          name: '待读单',
          bookIds: const <String>['local:b1'],
        );
        expect(
          (await colRepo.readListBooks(rl.id)).items.single.id,
          'local:b1',
        );

        // 物理文件被外部删除时，转换为 ShelfFailure 而非未捕获 FileSystemException
        await readerRepo.closeBookHandle('local:b1');
        await cbzFile.delete();
        await expectLater(
          () => readerRepo.pageImage('local:b1', 1),
          throwsA(isA<ShelfFailure>()),
        );
      },
    );
  });
}
