import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu/src/widgets/book_download_button.dart';
import 'package:yomu/src/widgets/series_book_row.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/fakes.dart';

void main() {
  group('单源隐形、多源分组切换与云端微标 UI 验证', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('yomu_multi_ui_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    testWidgets('纯本地未配服务器时：隐藏源分组栏，展示本机空态导入引导与顶栏 + 按钮', (
      WidgetTester tester,
    ) async {
      final db = ProgressDatabase(NativeDatabase.memory());
      final cacheDb = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await cacheDb.close();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            progressDatabaseProvider.overrideWithValue(db),
            httpCacheDatabaseProvider.overrideWithValue(cacheDb),
            localComicsStorageProvider.overrideWithValue(
              LocalComicsStorage(rootResolver: () async => tempDir),
            ),
            serverStoreProvider.overrideWithValue(InMemoryServerStore()),
            settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 单源隐形：不出现 source-group-bar
      expect(find.byKey(const Key('source-group-bar')), findsNothing);
      // 展示本机导入圆球与空书架引导
      expect(find.byKey(const Key('shelf-import-orb')), findsOneWidget);
      expect(find.byKey(const Key('shelf-local-onboarding')), findsOneWidget);
      expect(find.text('Your shelf is ready'), findsOneWidget);
    });

    testWidgets('同时存在本机与 Komga 服务器时：展示源分组胶囊并按分组切换，云端系列显示小云标', (
      WidgetTester tester,
    ) async {
      final db = ProgressDatabase(NativeDatabase.memory());
      final cacheDb = HttpCacheDatabase(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await cacheDb.close();
      });

      await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'local:b1',
          seriesTitle: 'Local Dungeon Meshi',
          bookName: 'Vol. 1',
          storageKind: 'zip',
          relativePath: 'b1.cbz',
          sizeBytes: 512,
          pages: <ArchivePageEntry>[
            ArchivePageEntry(
              number: 1,
              entryName: '1.jpg',
              uncompressedSize: 512,
            ),
          ],
        ),
        generateSeriesId: () => 'local:s1',
      );

      final server = storedServer();
      final cloudSeries = const Series(
        id: 'cloud-s1',
        libraryId: 'lib-1',
        title: 'Cloud Witch Hat',
        booksCount: 5,
      ).withSource(server.id);

      final localBundle = SourceBundle(
        source: const LocalContentSource(),
        library: FakeLibraryRepository(
          series: const <Series>[
            Series(
              id: 'local:s1',
              libraryId: kLocalLibraryId,
              title: 'Local Dungeon Meshi',
              booksCount: 1,
            ),
          ],
        ),
        reader: FakeReaderRepository(pageCount: 10),
        collections: FakeLibraryRepository(),
        readStatus: FakeLibraryRepository(),
      );
      final remoteBundle = SourceBundle(
        source: RemoteContentSource(
          sourceKey: server.id,
          displayName: 'Home NAS',
        ),
        library: FakeLibraryRepository(series: <Series>[cloudSeries]),
        reader: FakeReaderRepository(pageCount: 10),
        collections: FakeLibraryRepository(),
        readStatus: FakeLibraryRepository(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            progressDatabaseProvider.overrideWithValue(db),
            httpCacheDatabaseProvider.overrideWithValue(cacheDb),
            serverStoreProvider.overrideWithValue(InMemoryServerStore(server)),
            settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
            sourceRegistryProvider.overrideWithValue(
              SourceRegistry(
                localBundle: localBundle,
                remoteBundles: <String, SourceBundle>{server.id: remoteBundle},
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 默认恢复至已连接的 Home NAS，显示分组胶囊与云端系列小云标
      expect(find.byKey(const Key('source-group-bar')), findsOneWidget);
      expect(find.text('Cloud Witch Hat'), findsOneWidget);
      expect(find.byKey(const Key('series-cloud-cloud-s1')), findsOneWidget);

      // 点击「On Device」胶囊切回本机书架：展示本机漫画且无云端小图标
      await tester.tap(find.byKey(const Key('source-chip-local://device')));
      await tester.pumpAndSettle();

      expect(find.text('Local Dungeon Meshi'), findsOneWidget);
      expect(find.byKey(const Key('series-cloud-local:s1')), findsNothing);
    });

    testWidgets('本地书籍书行隐藏下载按钮，云端书籍书行保留下载按钮', (WidgetTester tester) async {
      const localBook = Book(
        id: 'local:b_1',
        seriesId: 'local:s_1',
        name: 'Vol. 1',
        pagesCount: 20,
      );
      final cloudBook = const Book(
        id: '0H8CLOUD1',
        seriesId: '0H8SERIES',
        name: 'Vol. 2',
        pagesCount: 20,
      ).withSource('https://komga.example.com');

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            libraryRepositoryProvider.overrideWithValue(
              FakeLibraryRepository(),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  SeriesBookRow(book: localBook, onOpen: () async {}),
                  SeriesBookRow(book: cloudBook, onOpen: () async {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BookDownloadButton), findsOneWidget);
    });
  });
}
