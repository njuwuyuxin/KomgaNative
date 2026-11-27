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
import 'package:yomu/src/router.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_sync/yomu_sync.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/fakes.dart';

const String _kServerA = 'https://komga-a.example';
const String _kServerB = 'https://komga-b.example:8443/sub';

class _FixedActiveSource extends ActiveSourceController {
  _FixedActiveSource(this._source);

  final ContentSource _source;

  @override
  ContentSource build() => _source;
}

void main() {
  group('P2-6 跨源路由扩展覆盖', () {
    testWidgets('多服务器隔离：激活服务器 A 时打开服务器 B 的书，仅命中 B 且进度写入 B 分区', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      const bookB = Book(
        id: 'book-b-1',
        seriesId: 'series-b-1',
        name: 'Server B Manga',
        number: '1',
        pagesCount: 3,
        sourceKey: _kServerB,
      );
      final localLib = FakeLibraryRepository(
        detailFailure: const NotFoundFailure(),
      );
      final localReader = FakeReaderRepository(
        pagesFailure: const NotFoundFailure(),
        imageFailure: const NotFoundFailure(),
      );
      final libA = FakeLibraryRepository(
        detailFailure: const NotFoundFailure(),
      );
      final readerA = FakeReaderRepository(
        pagesFailure: const NotFoundFailure(),
        imageFailure: const NotFoundFailure(),
      );
      final libB = FakeLibraryRepository();
      final readerB = FakeReaderRepository(stubBook: bookB, pageCount: 3);

      const sourceA = RemoteContentSource(
        sourceKey: _kServerA,
        displayName: 'Server A',
        subtitle: _kServerA,
      );
      const sourceB = RemoteContentSource(
        sourceKey: _kServerB,
        displayName: 'Server B',
        subtitle: _kServerB,
      );

      final registry = SourceRegistry(
        localBundle: SourceBundle(
          source: const LocalContentSource(),
          library: localLib,
          reader: localReader,
          collections: localLib,
          readStatus: localLib,
        ),
        remoteBundles: <String, SourceBundle>{
          _kServerA: SourceBundle(
            source: sourceA,
            library: libA,
            reader: readerA,
            collections: libA,
            readStatus: libA,
          ),
          _kServerB: SourceBundle(
            source: sourceB,
            library: libB,
            reader: readerB,
            collections: libB,
            readStatus: libB,
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
      final store = InMemoryProgressStore();
      final uploadedScopes = <String>[];
      final sync = ProgressSyncService(
        store: store,
        scopedUpload: (String scope, ProgressTarget _) async {
          uploadedScopes.add(scope);
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sourceRegistryProvider.overrideWithValue(registry),
            activeSourceProvider.overrideWith(
              () => _FixedActiveSource(sourceA),
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
              sourceKey: _kServerB,
              child: ReaderScreen(
                bookId: bookB.id,
                book: bookB,
                sourceKey: _kServerB,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reader-image-0')), findsOneWidget);
      expect(readerB.pageImageCalls, greaterThan(0));
      expect(readerA.pageImageCalls, 0);
      expect(localReader.pageImageCalls, 0);

      // 翻到下一页并越过 600ms 防抖后，进度必须真实写进 Server B，且绝不污染 Server A 或本机（N7）。
      final tapRect = tester.getRect(find.byKey(const Key('reader-tap-layer')));
      await tester.tapAt(
        Offset(tapRect.right - tapRect.width * 0.05, tapRect.center.dy),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      final savedB = await store.record(bookB.id, scope: _kServerB);
      expect(savedB, isNotNull);
      expect(savedB!.page, 2);
      expect(uploadedScopes, <String>[_kServerB]);
      expect(await store.record(bookB.id, scope: _kServerA), isNull);
      expect(await store.record(bookB.id, scope: kLocalSourceKey), isNull);
    });

    testWidgets('远程源已删除时按其 sourceKey 打开系列详情：绝不静默回退到本地库', (
      WidgetTester tester,
    ) async {
      final localLib = FakeLibraryRepository(
        series: const <Series>[
          Series(
            id: 'same-id',
            libraryId: 'local',
            title: 'Local Trap Series',
            booksCount: 1,
            sourceKey: kLocalSourceKey,
          ),
        ],
      );
      final localReader = FakeReaderRepository();
      final registry = SourceRegistry(
        localBundle: SourceBundle(
          source: const LocalContentSource(),
          library: localLib,
          reader: localReader,
          collections: localLib,
          readStatus: localLib,
        ),
        remoteBundles: const <String, SourceBundle>{},
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
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const ScopedSourceScope(
              sourceKey: 'https://removed-server.example',
              child: SeriesDetailScreen(
                seriesId: 'same-id',
                sourceKey: 'https://removed-server.example',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 绝不能展示同 ID 的本地陷阱系列。
      expect(find.text('Local Trap Series'), findsNothing);
    });

    testWidgets('GoRouter /series/:id?source= 带端口和路径的编码 URL 能准确路由到目标源', (
      WidgetTester tester,
    ) async {
      final localLib = FakeLibraryRepository(
        detailFailure: const NotFoundFailure(),
      );
      final localReader = FakeReaderRepository();
      final libB = FakeLibraryRepository(
        series: const <Series>[
          Series(
            id: 'srv-b-series',
            libraryId: 'lib1',
            title: 'Server B Deep Link Series',
            booksCount: 2,
            sourceKey: _kServerB,
          ),
        ],
      )..bookCount = 2;
      final readerB = FakeReaderRepository();
      const sourceB = RemoteContentSource(
        sourceKey: _kServerB,
        displayName: 'Server B',
        subtitle: _kServerB,
      );
      final registry = SourceRegistry(
        localBundle: SourceBundle(
          source: const LocalContentSource(),
          library: localLib,
          reader: localReader,
          collections: localLib,
          readStatus: localLib,
        ),
        remoteBundles: <String, SourceBundle>{
          _kServerB: SourceBundle(
            source: sourceB,
            library: libB,
            reader: readerB,
            collections: libB,
            readStatus: libB,
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

      final session = ValueNotifier<SessionState>(const SessionDisconnected());
      addTearDown(session.dispose);
      final encodedSource = Uri.encodeQueryComponent(_kServerB);
      final router = createRouter(
        session: session,
        initialLocation: '/series/srv-b-series?source=$encodedSource',
      );
      addTearDown(router.dispose);

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
          ],
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server B Deep Link Series'), findsOneWidget);
    });
  });
}
