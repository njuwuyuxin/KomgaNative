import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/cache/drift_http_cache.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_sync/yomu_sync.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/fakes.dart';

const String _kRemoteSourceKey = 'https://komga.example';

class _FixedActiveSource extends ActiveSourceController {
  _FixedActiveSource(this._source);

  final ContentSource _source;

  @override
  ContentSource build() => _source;
}

void main() {
  testWidgets('Komga 分组激活时跨源打开本地书：阅读器必须路由到本机仓库而非 Komga 仓库', (
    WidgetTester tester,
  ) async {
    const localBook = Book(
      id: 'local:book-1',
      seriesId: 'local:series-1',
      name: 'Local Manga Vol. 1',
      number: '1',
      pagesCount: 3,
      sourceKey: kLocalSourceKey,
    );
    final localLibrary = FakeLibraryRepository(
      series: const <Series>[
        Series(
          id: 'local:series-1',
          libraryId: 'local',
          title: 'Local Manga',
          booksCount: 1,
          sourceKey: kLocalSourceKey,
        ),
      ],
    );
    final localReader = FakeReaderRepository(stubBook: localBook, pageCount: 3);

    // 远程 Komga 仓库故意对所有请求返回 NotFoundFailure：
    // 如果派生 provider 错误地落回激活源（Komga），阅读器会直接报错页。
    final remoteLibrary = FakeLibraryRepository(
      detailFailure: const NotFoundFailure(),
      booksFailure: const NotFoundFailure(),
    );
    final remoteReader = FakeReaderRepository(
      pagesFailure: const NotFoundFailure(),
      imageFailure: const NotFoundFailure(),
    );

    const remoteSource = RemoteContentSource(
      sourceKey: _kRemoteSourceKey,
      displayName: 'Home Komga',
      subtitle: _kRemoteSourceKey,
    );
    final registry = SourceRegistry(
      localBundle: SourceBundle(
        source: const LocalContentSource(),
        library: localLibrary,
        reader: localReader,
        collections: localLibrary,
        readStatus: localLibrary,
      ),
      remoteBundles: <String, SourceBundle>{
        _kRemoteSourceKey: SourceBundle(
          source: remoteSource,
          library: remoteLibrary,
          reader: remoteReader,
          collections: remoteLibrary,
          readStatus: remoteLibrary,
        ),
      },
    );

    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = DriftHttpCache(
      HttpCacheDatabase(NativeDatabase.memory()),
      now: () => DateTime.utc(2026, 11, 25, 12),
    );
    addTearDown(cache.dispose);
    final sync = ProgressSyncService(
      store: InMemoryProgressStore(),
      upload: (ProgressTarget _) async {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sourceRegistryProvider.overrideWithValue(registry),
          activeSourceProvider.overrideWith(
            () => _FixedActiveSource(remoteSource),
          ),
          progressDatabaseProvider.overrideWithValue(db),
          progressSyncProvider.overrideWithValue(sync),
          httpCacheProvider.overrideWithValue(cache),
          readerPrefsStoreProvider.overrideWithValue(
            InMemoryReaderPrefsStore(),
          ),
          wakeLockProvider.overrideWithValue(FakeWakeLock()),
          imageSaverProvider.overrideWithValue(FakeImageSaver()),
          hardwareKeysProvider.overrideWithValue(FakeHardwareKeys()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.dark(),
          home: ScopedSourceScope(
            sourceKey: kLocalSourceKey,
            child: ReaderScreen(bookId: localBook.id, book: localBook),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 必须成功渲染本地书第一页，且远程 Komga 仓库零调用。
    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    expect(localReader.pageImageCalls, greaterThan(0));
    expect(remoteReader.pageImageCalls, 0);
  });

  testWidgets('Komga 分组激活时跨源打开本地系列详情：必须路由到本机仓库而非 Komga 仓库', (
    WidgetTester tester,
  ) async {
    final localLibrary = FakeLibraryRepository(
      series: const <Series>[
        Series(
          id: 'local:series-1',
          libraryId: 'local',
          title: 'Local Exclusive Series',
          booksCount: 2,
          sourceKey: kLocalSourceKey,
        ),
      ],
    )..bookCount = 2;
    final localReader = FakeReaderRepository();

    final remoteLibrary = FakeLibraryRepository(
      detailFailure: const NotFoundFailure(),
      booksFailure: const NotFoundFailure(),
    );
    final remoteReader = FakeReaderRepository();

    const remoteSource = RemoteContentSource(
      sourceKey: _kRemoteSourceKey,
      displayName: 'Home Komga',
      subtitle: _kRemoteSourceKey,
    );
    final registry = SourceRegistry(
      localBundle: SourceBundle(
        source: const LocalContentSource(),
        library: localLibrary,
        reader: localReader,
        collections: localLibrary,
        readStatus: localLibrary,
      ),
      remoteBundles: <String, SourceBundle>{
        _kRemoteSourceKey: SourceBundle(
          source: remoteSource,
          library: remoteLibrary,
          reader: remoteReader,
          collections: remoteLibrary,
          readStatus: remoteLibrary,
        ),
      },
    );

    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = DriftHttpCache(
      HttpCacheDatabase(NativeDatabase.memory()),
      now: () => DateTime.utc(2026, 11, 25, 12),
    );
    addTearDown(cache.dispose);
    final sync = ProgressSyncService(
      store: InMemoryProgressStore(),
      upload: (ProgressTarget _) async {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sourceRegistryProvider.overrideWithValue(registry),
          activeSourceProvider.overrideWith(
            () => _FixedActiveSource(remoteSource),
          ),
          progressDatabaseProvider.overrideWithValue(db),
          progressSyncProvider.overrideWithValue(sync),
          httpCacheProvider.overrideWithValue(cache),
          readerPrefsStoreProvider.overrideWithValue(
            InMemoryReaderPrefsStore(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const ScopedSourceScope(
            sourceKey: kLocalSourceKey,
            child: SeriesDetailScreen(seriesId: 'local:series-1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local Exclusive Series'), findsOneWidget);
  });

  testWidgets('本机分组激活时跨源打开 Komga 书与系列详情：必须路由到 Komga 仓库而非本机仓库', (
    WidgetTester tester,
  ) async {
    const remoteBook = Book(
      id: 'remote-book-1',
      seriesId: 'remote-series-1',
      name: 'Cloud Manga Vol. 1',
      number: '1',
      pagesCount: 3,
      sourceKey: _kRemoteSourceKey,
    );
    final remoteLibrary = FakeLibraryRepository(
      series: const <Series>[
        Series(
          id: 'remote-series-1',
          libraryId: 'lib1',
          title: 'Cloud Exclusive Series',
          booksCount: 2,
          sourceKey: _kRemoteSourceKey,
        ),
      ],
    )..bookCount = 2;
    final remoteReader = FakeReaderRepository(
      stubBook: remoteBook,
      pageCount: 3,
    );

    final localLibrary = FakeLibraryRepository(
      detailFailure: const NotFoundFailure(),
      booksFailure: const NotFoundFailure(),
    );
    final localReader = FakeReaderRepository(
      pagesFailure: const NotFoundFailure(),
      imageFailure: const NotFoundFailure(),
    );

    const remoteSource = RemoteContentSource(
      sourceKey: _kRemoteSourceKey,
      displayName: 'Home Komga',
      subtitle: _kRemoteSourceKey,
    );
    final registry = SourceRegistry(
      localBundle: SourceBundle(
        source: const LocalContentSource(),
        library: localLibrary,
        reader: localReader,
        collections: localLibrary,
        readStatus: localLibrary,
      ),
      remoteBundles: <String, SourceBundle>{
        _kRemoteSourceKey: SourceBundle(
          source: remoteSource,
          library: remoteLibrary,
          reader: remoteReader,
          collections: remoteLibrary,
          readStatus: remoteLibrary,
        ),
      },
    );

    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cache = DriftHttpCache(
      HttpCacheDatabase(NativeDatabase.memory()),
      now: () => DateTime.utc(2026, 11, 25, 12),
    );
    addTearDown(cache.dispose);
    final sync = ProgressSyncService(
      store: InMemoryProgressStore(),
      upload: (ProgressTarget _) async {},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sourceRegistryProvider.overrideWithValue(registry),
          activeSourceProvider.overrideWith(
            () => _FixedActiveSource(const LocalContentSource()),
          ),
          progressDatabaseProvider.overrideWithValue(db),
          progressSyncProvider.overrideWithValue(sync),
          httpCacheProvider.overrideWithValue(cache),
          readerPrefsStoreProvider.overrideWithValue(
            InMemoryReaderPrefsStore(),
          ),
          wakeLockProvider.overrideWithValue(FakeWakeLock()),
          imageSaverProvider.overrideWithValue(FakeImageSaver()),
          hardwareKeysProvider.overrideWithValue(FakeHardwareKeys()),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.dark(),
          home: ReaderScreen(
            bookId: remoteBook.id,
            book: remoteBook,
            sourceKey: _kRemoteSourceKey,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
    expect(remoteReader.pageImageCalls, greaterThan(0));
    expect(localReader.pageImageCalls, 0);
  });
}
