import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/local_curation_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/local_catalog_mutator_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('LMA-10 本地元数据编辑、散装单卷合并与拆分系列', () {
    late Directory tempDir;
    late ProgressDatabase db;
    late ProviderContainer container;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('yomu_edit_');
      db = ProgressDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          serverStoreProvider.overrideWithValue(InMemoryServerStore()),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(
            LocalComicsStorage(rootResolver: () async => tempDir),
          ),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('散装 3 个单本系列合并为 1 个系列、修改卷号重排、锁定元数据，并支持拆出独立系列', () async {
      for (final (sid, bid, title) in <(String, String, String)>[
        ('local:s_1', 'local:b_3', '杂乱命名_第三卷'),
        ('local:s_2', 'local:b_1', '第一卷_正式版'),
        ('local:s_3', 'local:b_2', '第二卷_修正'),
      ]) {
        await db.insertImportedLocalBook(
          LocalBookImportDraft(
            bookId: bid,
            seriesIdOverride: sid,
            seriesTitle: title,
            bookName: title,
            storageKind: 'zip',
            relativePath: '$bid.cbz',
            sizeBytes: 100,
            pages: const <ArchivePageEntry>[
              ArchivePageEntry(
                number: 1,
                entryName: '01.jpg',
                uncompressedSize: 100,
              ),
            ],
          ),
          generateSeriesId: () => sid,
        );
      }

      await db.insertLocalCollection(
        id: 'local:col_merge',
        name: '追漫夹',
        seriesIds: const <String>['local:s_1', 'local:s_2'],
      );

      final mutator = container.read(localCatalogMutatorProvider);
      await mutator.mergeSeries(
        sourceSeriesIds: const <String>['local:s_1', 'local:s_2', 'local:s_3'],
        targetSeriesId: 'local:s_1',
        mergedTitle: '迷宫饭',
      );

      final allSeries = (await db.queryLocalSeries()).items;
      expect(allSeries, hasLength(1));
      expect(allSeries.single.id, 'local:s_1');
      expect(allSeries.single.title, '迷宫饭');
      expect(allSeries.single.booksCount, 3);

      // 收藏集中的旧源系列引用已自动去重替换为目标系列
      expect(
        (await db.localCollectionById('local:col_merge'))?.seriesIds,
        const <String>['local:s_1'],
      );

      // 修改系列阅读方向与作者，并修正三本书的卷号 1, 2, 3
      await mutator.editSeries(
        'local:s_1',
        title: '迷宫饭（精校）',
        authors: const <String>['九井谅子'],
        tags: const <String>['奇幻', '美食'],
        summary: '地下城美食冒险',
        readingDirection: ReadingDirection.rightToLeft,
      );
      await mutator.editBook(
        'local:b_1',
        seriesId: 'local:s_1',
        name: '第 1 卷',
        number: '1',
      );
      await mutator.editBook(
        'local:b_2',
        seriesId: 'local:s_1',
        name: '第 2 卷',
        number: '2',
      );
      await mutator.editBook(
        'local:b_3',
        seriesId: 'local:s_1',
        name: '番外篇',
        number: '2.5',
      );

      final editedSeries = await db.localSeriesById('local:s_1');
      expect(editedSeries?.title, '迷宫饭（精校）');
      expect(editedSeries?.readingDirection, ReadingDirection.rightToLeft);
      expect(editedSeries?.authors, const <String>['九井谅子']);

      final orderedBooks = (await db.queryLocalSeriesBooks('local:s_1')).items;
      expect(orderedBooks.map((b) => b.id), const <String>[
        'local:b_1',
        'local:b_2',
        'local:b_3',
      ]);

      // 将番外篇拆出为独立系列
      final splitSeriesId = await mutator.splitBookToOwnSeries(
        'local:b_3',
        currentSeriesId: 'local:s_1',
      );
      expect(splitSeriesId, isNotNull);
      expect(splitSeriesId, isNot('local:s_1'));
      expect((await db.localSeriesById('local:s_1'))?.booksCount, 2);
      expect((await db.localSeriesById(splitSeriesId!))?.booksCount, 1);
      expect((await db.localSeriesById(splitSeriesId))?.title, '番外篇');
    });

    test('LMA-11 将阅读器指定页设为自定义封面后，书籍与系列封面即时更新', () async {
      final pagesDir = Directory('${tempDir.path}/books/b_cov/pages')
        ..createSync(recursive: true);
      await File('${pagesDir.path}/01.png').writeAsBytes(const <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        1,
      ]);
      await File('${pagesDir.path}/02.png').writeAsBytes(const <int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        99,
      ]);

      await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'local:b_cov',
          seriesIdOverride: 'local:s_cov',
          seriesTitle: 'Cover Test',
          bookName: 'Vol. 1',
          storageKind: 'folder',
          relativePath: 'books/b_cov/pages',
          sizeBytes: 18,
          pages: <ArchivePageEntry>[
            ArchivePageEntry(
              number: 1,
              entryName: '01.png',
              uncompressedSize: 9,
            ),
            ArchivePageEntry(
              number: 2,
              entryName: '02.png',
              uncompressedSize: 9,
            ),
          ],
        ),
        generateSeriesId: () => 'local:s_cov',
      );

      final libRepo = container.read(localLibraryRepositoryProvider);
      expect((await libRepo.seriesCover('local:s_cov'))?.last, 1);

      final ok = await container
          .read(localCatalogMutatorProvider)
          .setCustomCoverFromPageBytes(
            bookId: 'local:b_cov',
            seriesId: 'local:s_cov',
            pageNumber: 2,
          );
      expect(ok, isTrue);

      final updatedCover = await libRepo.seriesCover('local:s_cov');
      expect(updatedCover?.last, 99, reason: '系列封面应已替换为第 2 页');
    });
  });
}
