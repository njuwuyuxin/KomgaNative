import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/screens/downloads_screen.dart';
import 'package:yomu/src/screens/reader_args.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';
import 'support/test_source_overrides.dart';

void main() {
  const serverUrl = 'https://komga-a.example.com';
  final server = StoredServer(
    address: ServerAddress.parse(serverUrl),
    apiKey: 'k-a',
    accountEmail: 'a@example.com',
  );

  SourceBundle makeBundle({
    required ContentSource source,
    required FakeLibraryRepository library,
    DownloadService download = const NoopDownloadService(),
  }) {
    return SourceBundle(
      source: source,
      library: library,
      reader: FakeReaderRepository(),
      collections: library,
      readStatus: library,
      download: download,
    );
  }

  testWidgets('本机分组下点击已下载云端书：即使元数据查询返回空，仍携带云端 sourceKey 打开阅读器', (
    WidgetTester tester,
  ) async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.markDownloaded(
      scope: serverUrl,
      bookId: 'komga-book-1',
      seriesId: 'komga-series-1',
      bookName: 'Cloud Manga Vol. 1',
      pageCount: 24,
      bytes: 1024 * 1024,
    );

    final localLib = _SpyLibraryRepository();
    final remoteLib = _SpyLibraryRepository(bookResult: null);
    final registry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: localLib,
      ),
      remoteBundles: <String, SourceBundle>{
        serverUrl: makeBundle(
          source: remoteSourceOfServer(server),
          library: remoteLib,
        ),
      },
    );

    Uri? pushedUri;
    ReaderArgs? pushedArgs;
    final router = GoRouter(
      initialLocation: '/downloads',
      routes: <RouteBase>[
        GoRoute(path: '/downloads', builder: (_, _) => const DownloadsScreen()),
        GoRoute(
          path: '/reader/:bookId',
          builder: (_, GoRouterState state) {
            pushedUri = state.uri;
            pushedArgs = state.extra as ReaderArgs?;
            return const Scaffold(body: Text('reader-stub'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sourceRegistryProvider.overrideWithValue(registry),
          httpCacheDatabaseProvider.overrideWithValue(db),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
          activeSourceProvider.overrideWith(
            () => FixedActiveSourceController(const LocalContentSource()),
          ),
          sessionProvider.overrideWith(
            () => _FixedSessionController(SessionConnected(server)),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      localLib.queriedBookIds,
      isEmpty,
      reason: '本机分组下展示云端下载项，不得去本机库查云端书 ID',
    );
    expect(remoteLib.queriedBookIds, contains('komga-book-1'));

    await tester.tap(find.byKey(const Key('download-komga-book-1')));
    await tester.pumpAndSettle();

    expect(pushedUri?.path, '/reader/komga-book-1');
    expect(pushedUri?.queryParameters['source'], serverUrl);
    expect(pushedArgs, isNotNull);
    expect(pushedArgs!.sourceKey, serverUrl);
    expect(pushedArgs!.book.sourceKey, serverUrl);
    expect(pushedArgs!.book.isCloud, isTrue);
  });

  test('本机分组下 retryOne 走远端 scope 的 LibraryRepository 解析并交回远端下载服务', () async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final cloudBook = const Book(
      id: 'komga-book-2',
      seriesId: 'komga-series-2',
      name: 'Cloud Vol. 2',
      pagesCount: 16,
    ).withSource(serverUrl);
    final localLib = _SpyLibraryRepository();
    final remoteLib = _SpyLibraryRepository(bookResult: cloudBook);
    final remoteDownload = _SpyDownloadService();
    final registry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: localLib,
      ),
      remoteBundles: <String, SourceBundle>{
        serverUrl: makeBundle(
          source: remoteSourceOfServer(server),
          library: remoteLib,
          download: remoteDownload,
        ),
      },
    );

    final container = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        httpCacheDatabaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        activeSourceProvider.overrideWith(
          () => FixedActiveSourceController(const LocalContentSource()),
        ),
        sessionProvider.overrideWith(
          () => _FixedSessionController(SessionConnected(server)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final ok = await container
        .read(downloadsProvider.notifier)
        .retryOne('komga-book-2');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(ok, isTrue);
    expect(localLib.queriedBookIds, isEmpty);
    expect(remoteLib.queriedBookIds, <String>['komga-book-2']);
    expect(remoteDownload.startedBooks.single.id, 'komga-book-2');
    expect(remoteDownload.startedBooks.single.sourceKey, serverUrl);
  });

  test('远端查书抛 ShelfFailure 时 bookByIdProvider 温和返回 null 而非炸掉列表', () async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final remoteLib = _SpyLibraryRepository(throwOnBook: true);
    final registry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: _SpyLibraryRepository(),
      ),
      remoteBundles: <String, SourceBundle>{
        serverUrl: makeBundle(
          source: remoteSourceOfServer(server),
          library: remoteLib,
        ),
      },
    );

    final container = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        httpCacheDatabaseProvider.overrideWithValue(db),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        activeSourceProvider.overrideWith(
          () => FixedActiveSourceController(const LocalContentSource()),
        ),
        sessionProvider.overrideWith(
          () => _FixedSessionController(SessionConnected(server)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      bookByIdProvider((sourceKey: serverUrl, bookId: 'missing-1')).future,
    );
    expect(result, isNull);
  });
}

final class _FixedSessionController extends SessionController {
  _FixedSessionController(this._state);
  final SessionState _state;

  @override
  SessionState build() => _state;
}

final class _SpyLibraryRepository extends FakeLibraryRepository {
  _SpyLibraryRepository({this.bookResult, this.throwOnBook = false});

  final Book? bookResult;
  final bool throwOnBook;
  final List<String> queriedBookIds = <String>[];

  @override
  Future<Book?> book(String bookId) async {
    queriedBookIds.add(bookId);
    if (throwOnBook) throw const NetworkFailure();
    return bookResult;
  }
}

final class _SpyDownloadService implements DownloadService {
  final List<Book> startedBooks = <Book>[];

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    startedBooks.add(book);
    onProgress(DownloadProgress(done: book.pagesCount, total: book.pagesCount));
    return true;
  }

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  void cancel(String bookId) {}

  @override
  Future<void> delete(Book book) async {}
}
