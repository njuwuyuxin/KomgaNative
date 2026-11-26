import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:yomu/src/data/local/local_catalog_ondeck_dao.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_curation_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_sync/yomu_sync.dart';

void main() {
  group('ProgressDatabase v3 -> v4 迁移与本地目录/收藏集/进度直写', () {
    test('从 v3 数据库升级到 v4 保留全部旧数据并创建本地书目与收藏表', () async {
      final tempDir = Directory.systemTemp.createTempSync('yomu_v3_v4_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final dbFile = File('${tempDir.path}/komga_native.sqlite');

      final raw = sqlite.sqlite3.open(dbFile.path);
      raw.execute('''
        CREATE TABLE local_progress (
          scope TEXT NOT NULL DEFAULT '',
          book_id TEXT NOT NULL,
          page INTEGER NOT NULL,
          completed INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          server_last_modified INTEGER NULL,
          pending_seq INTEGER NULL,
          PRIMARY KEY (scope, book_id)
        );
        CREATE TABLE pinned_series_rows (
          server_id TEXT NOT NULL,
          series_id TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (server_id, series_id)
        );
        CREATE TABLE reading_sessions (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          scope TEXT NOT NULL DEFAULT '',
          book_id TEXT NOT NULL,
          series_id TEXT NOT NULL,
          book_name TEXT NOT NULL DEFAULT '',
          started_at INTEGER NOT NULL,
          ended_at INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL,
          start_page INTEGER NOT NULL DEFAULT 1,
          end_page INTEGER NOT NULL DEFAULT 1,
          completed INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO local_progress (scope, book_id, page, completed, updated_at, pending_seq)
        VALUES ('https://komga.example.com', 'remote-b1', 9, 0, 1700000100, 77);
        PRAGMA user_version = 3;
      ''');
      raw.close();

      final db = ProgressDatabase(NativeDatabase(dbFile));
      addTearDown(db.close);

      final existing = await db.record(
        'remote-b1',
        scope: 'https://komga.example.com',
      );
      expect(existing?.page, 9);
      expect(existing?.pendingSeq, 77);
      expect((await db.queryLocalSeries()).items, isEmpty);
      expect((await db.queryLocalCollections()).items, isEmpty);
    });

    test('同名系列自动归并、排序/阅读状态筛选、本地 ondeck 下一卷推导与纯本地进度直写', () async {
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      var remoteUploads = 0;
      final sync = ProgressSyncService(
        store: DriftProgressStore(db),
        activeScope: () => kLocalSourceKey,
        scopedUpload: (String scope, ProgressTarget target) async {
          remoteUploads++;
        },
      );

      var idCounter = 0;
      String nextSeriesId() => 'local:s_${++idCounter}';

      final r1 = await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'local:b_1',
          seriesTitle: '葬送的芙莉莲',
          bookName: 'Vol. 1',
          number: '1',
          numberSort: 1,
          authors: const <String>['山田钟人'],
          tags: const <String>['奇幻'],
          readingDirection: ReadingDirection.rightToLeft,
          storageKind: 'zip',
          relativePath: 'local_b_1/vol1.cbz',
          sizeBytes: 1024,
          pages: const <ArchivePageEntry>[
            ArchivePageEntry(
              number: 1,
              entryName: '01.jpg',
              uncompressedSize: 500,
              width: 800,
              height: 1200,
            ),
            ArchivePageEntry(
              number: 2,
              entryName: '02.jpg',
              uncompressedSize: 524,
              width: 800,
              height: 1200,
            ),
          ],
        ),
        generateSeriesId: nextSeriesId,
      );

      final r2 = await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'local:b_2',
          seriesTitle: '葬送的芙莉莲',
          bookName: 'Vol. 2',
          number: '2',
          numberSort: 2,
          tags: const <String>['冒险'],
          storageKind: 'zip',
          relativePath: 'local_b_2/vol2.cbz',
          sizeBytes: 2048,
          pages: const <ArchivePageEntry>[
            ArchivePageEntry(
              number: 1,
              entryName: '01.jpg',
              uncompressedSize: 2048,
            ),
          ],
        ),
        generateSeriesId: nextSeriesId,
      );

      expect(r2.seriesId, r1.seriesId, reason: '同名系列应自动归并');
      final usage = await db.localStorageUsage();
      expect(usage.booksCount, 2);
      expect(usage.totalBytes, 3072);

      // 未读筛选
      final unreadShelf = await db.queryLocalSeries(
        readStatus: SeriesReadStatus.unread,
      );
      expect(unreadShelf.items, hasLength(1));
      expect(unreadShelf.items.single.booksCount, 2);
      expect(unreadShelf.items.single.booksReadCount, 0);
      expect(unreadShelf.items.single.isCloud, isFalse);

      // 本地翻到第 1 页：直接落盘，pending 队列为空，绝不触发网络上传
      await sync.save(
        'local:b_1',
        page: 1,
        completed: false,
        scope: kLocalSourceKey,
      );
      expect(remoteUploads, 0);
      expect(await db.pending(scope: kLocalSourceKey), isEmpty);

      final inProgressOndeck = await db.localOndeck();
      expect(inProgressOndeck.items.map((b) => b.id), <String>['local:b_1']);
      expect(inProgressOndeck.items.single.readProgress?.page, 1);

      // 读完第 1 卷后：ondeck 自动推导第 2 卷未读（Up Next）
      await sync.save(
        'local:b_1',
        page: 2,
        completed: true,
        scope: kLocalSourceKey,
      );
      final upNextOndeck = await db.localOndeck();
      expect(upNextOndeck.items.map((b) => b.id), <String>['local:b_2']);
      expect((await db.localSeriesById(r1.seriesId))?.booksReadCount, 1);
    });

    test('本地收藏集与阅读列表完整 CRUD 并保留指定顺序', () async {
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      for (final (sid, title) in <(String, String)>[
        ('local:s_b', 'Berserk'),
        ('local:s_a', 'Akira'),
      ]) {
        await db.insertImportedLocalBook(
          LocalBookImportDraft(
            bookId: 'book_$sid',
            seriesIdOverride: sid,
            seriesTitle: title,
            bookName: '$title Vol.1',
            storageKind: 'zip',
            relativePath: '$sid.cbz',
            sizeBytes: 100,
            pages: const <ArchivePageEntry>[
              ArchivePageEntry(
                number: 1,
                entryName: '1.jpg',
                uncompressedSize: 100,
              ),
            ],
          ),
          generateSeriesId: () => sid,
        );
      }

      final col = await db.insertLocalCollection(
        id: 'local:c_1',
        name: '必看神作',
        ordered: true,
        seriesIds: const <String>['local:s_b', 'local:s_a'],
      );
      expect(col.isCloud, isFalse);
      final colSeries = await db.queryLocalCollectionSeries('local:c_1');
      expect(colSeries.items.map((s) => s.id), <String>[
        'local:s_b',
        'local:s_a',
      ]);

      await db.modifyLocalCollection('local:c_1', name: '殿堂作');
      expect((await db.localCollectionById('local:c_1'))?.name, '殿堂作');
      expect(await db.localSeriesCollections('local:s_a'), hasLength(1));

      final rl = await db.insertLocalReadList(
        id: 'local:rl_1',
        name: '周末补漫',
        summary: '按顺序读',
        ordered: true,
        bookIds: const <String>['book_local:s_a', 'book_local:s_b'],
      );
      expect(rl.bookCount, 2);
      final rlBooks = await db.queryLocalReadListBooks('local:rl_1');
      expect(rlBooks.items.map((b) => b.id), <String>[
        'book_local:s_a',
        'book_local:s_b',
      ]);

      await db.removeLocalCollection('local:c_1');
      await db.removeLocalReadList('local:rl_1');
      expect(await db.localCollectionById('local:c_1'), isNull);
      expect(await db.localReadListById('local:rl_1'), isNull);
    });
  });
}
