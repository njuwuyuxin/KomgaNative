import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

import 'support/fake_library.dart';
import 'support/fake_reader.dart';

class _RecordingDownloadService implements DownloadService {
  final List<String> downloadedIds = <String>[];
  final Map<String, DownloadedBook> _records = <String, DownloadedBook>{};

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => _records[bookId];

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    downloadedIds.add(book.id);
    onProgress(const DownloadProgress(done: 1, total: 1));
    _records[book.id] = DownloadedBook(
      scope: book.sourceKey,
      bookId: book.id,
      seriesId: book.seriesId,
      bookName: book.name,
      pageCount: 1,
      bytes: 100,
      savedAt: DateTime.utc(2026, 11, 26),
    );
    return true;
  }

  @override
  void cancel(String bookId) {}

  @override
  Future<void> delete(Book book) async {
    _records.remove(book.id);
  }
}

class _FixedSessionController extends SessionController {
  _FixedSessionController(this._initial);

  final SessionState _initial;
  int switchToCalls = 0;

  @override
  SessionState build() => _initial;

  @override
  Future<void> switchTo(StoredServer server) async {
    switchToCalls++;
  }
}

void main() {
  const serverAKey = 'https://alpha.komga.test';
  const serverBKey = 'https://beta.komga.test';

  final serverA = StoredServer(
    address: ServerAddress.parse(serverAKey),
    apiKey: 'key-a',
    accountEmail: 'a@komga.test',
  );
  final serverB = StoredServer(
    address: ServerAddress.parse(serverBKey),
    apiKey: 'key-b',
    accountEmail: 'b@komga.test',
  );

  SourceBundle makeBundle({
    required ContentSource source,
    required FakeLibraryRepository library,
    DownloadService download = const NoopDownloadService(),
  }) => SourceBundle(
    source: source,
    library: library,
    reader: FakeReaderRepository(),
    collections: library,
    readStatus: library,
    download: download,
  );

  test('crossSourceOndeckProvider 汇聚本机 + 多台远程服务器且单服故障隔离', () async {
    final localBook = Book(
      id: 'local-b1',
      seriesId: 'local-s1',
      name: 'Local Book',
      pagesCount: 20,
      readProgress: ReadProgress(
        page: 5,
        completed: false,
        lastModified: DateTime.utc(2026, 11, 26, 10),
      ),
    );
    final bookA = Book(
      id: 'a-b1',
      seriesId: 'a-s1',
      name: 'Alpha Book',
      pagesCount: 20,
      readProgress: ReadProgress(
        page: 8,
        completed: false,
        lastModified: DateTime.utc(2026, 11, 26, 12),
      ),
    ).withSource(serverAKey);
    final bookB = Book(
      id: 'b-b1',
      seriesId: 'b-s1',
      name: 'Beta Book',
      pagesCount: 20,
      readProgress: ReadProgress(
        page: 3,
        completed: false,
        lastModified: DateTime.utc(2026, 11, 26, 11),
      ),
    ).withSource(serverBKey);

    final registry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: FakeLibraryRepository(ondeck: <Book>[localBook]),
      ),
      remoteBundles: <String, SourceBundle>{
        serverAKey: makeBundle(
          source: remoteSourceOfServer(serverA),
          library: FakeLibraryRepository(ondeck: <Book>[bookA]),
        ),
        serverBKey: makeBundle(
          source: remoteSourceOfServer(serverB),
          library: FakeLibraryRepository(ondeck: <Book>[bookB]),
        ),
      },
    );

    final container = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        sessionProvider.overrideWith(
          () => _FixedSessionController(SessionConnected(serverA)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final page = await container.read(crossSourceOndeckProvider.future);
    expect(
      page.items.map((Book b) => '${b.sourceKey}:${b.id}').toList(),
      <String>[
        '$serverAKey:a-b1',
        '$serverBKey:b-b1',
        '$kLocalSourceKey:local-b1',
      ],
    );

    // 故障隔离：服务器 B 断网失败，本机与服务器 A 照常汇聚。
    final faultyRegistry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: FakeLibraryRepository(ondeck: <Book>[localBook]),
      ),
      remoteBundles: <String, SourceBundle>{
        serverAKey: makeBundle(
          source: remoteSourceOfServer(serverA),
          library: FakeLibraryRepository(ondeck: <Book>[bookA]),
        ),
        serverBKey: makeBundle(
          source: remoteSourceOfServer(serverB),
          library: FakeLibraryRepository(ondeckFailure: const NetworkFailure()),
        ),
      },
    );
    final faultyContainer = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(faultyRegistry),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    addTearDown(faultyContainer.dispose);

    final degraded = await faultyContainer.read(
      crossSourceOndeckProvider.future,
    );
    expect(degraded.items.map((Book b) => b.id).toList(), <String>[
      'a-b1',
      'local-b1',
    ]);
  });

  test('服务器 B 激活时下载服务器 A 的书籍：必须经 A 的 DownloadService 执行', () async {
    final dlA = _RecordingDownloadService();
    final dlB = _RecordingDownloadService();
    final cacheDb = HttpCacheDatabase(NativeDatabase.memory());
    addTearDown(cacheDb.close);

    final registry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: FakeLibraryRepository(),
      ),
      remoteBundles: <String, SourceBundle>{
        serverAKey: makeBundle(
          source: remoteSourceOfServer(serverA),
          library: FakeLibraryRepository(),
          download: dlA,
        ),
        serverBKey: makeBundle(
          source: remoteSourceOfServer(serverB),
          library: FakeLibraryRepository(),
          download: dlB,
        ),
      },
    );

    final container = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        httpCacheDatabaseProvider.overrideWithValue(cacheDb),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        sessionProvider.overrideWith(
          () => _FixedSessionController(SessionConnected(serverB)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(activeSourceProvider.notifier)
        .selectSource(serverBKey);
    final bookOnA = const Book(
      id: 'book-a-1',
      seriesId: 'series-a-1',
      name: 'Alpha Vol.1',
      pagesCount: 10,
    ).withSource(serverAKey);

    await container.read(downloadsProvider.notifier).start(bookOnA);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(dlA.downloadedIds, <String>['book-a-1']);
    expect(dlB.downloadedIds, isEmpty);
    final savedOnA = await container.read(
      downloadedForSourceProvider((sourceKey: serverAKey, bookId: 'book-a-1'))
          .future,
    );
    expect(savedOnA?.bookId, 'book-a-1');
  });

  test('selectSource 切换内容源分组不强行触发 sessionProvider.switchTo', () async {
    final sessionCtrl = _FixedSessionController(SessionConnected(serverA));
    final registry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: FakeLibraryRepository(),
      ),
      remoteBundles: <String, SourceBundle>{
        serverAKey: makeBundle(
          source: remoteSourceOfServer(serverA),
          library: FakeLibraryRepository(),
        ),
        serverBKey: makeBundle(
          source: remoteSourceOfServer(serverB),
          library: FakeLibraryRepository(),
        ),
      },
    );

    final container = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        sessionProvider.overrideWith(() => sessionCtrl),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(activeSourceProvider.notifier)
        .selectSource(serverBKey);
    expect(container.read(activeSourceProvider).sourceKey, serverBKey);
    expect(sessionCtrl.switchToCalls, 0);
  });

  test('未知或已删除的 sourceKey 能力查询返回最保守能力集 SourceCapabilities.none', () {
    final registry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: FakeLibraryRepository(),
      ),
      remoteBundles: <String, SourceBundle>{
        serverAKey: makeBundle(
          source: remoteSourceOfServer(serverA),
          library: FakeLibraryRepository(),
        ),
      },
    );

    final container = ProviderContainer(
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(sourceCapabilitiesForKeyProvider(kLocalSourceKey)),
      same(SourceCapabilities.local),
    );
    expect(
      container.read(sourceCapabilitiesForKeyProvider(serverAKey)),
      same(SourceCapabilities.komga),
    );
    final unknownCaps = container.read(
      sourceCapabilitiesForKeyProvider('https://deleted-server.komga.test'),
    );
    expect(unknownCaps, same(SourceCapabilities.none));
    expect(unknownCaps.canDownloadOffline, isFalse);
    expect(unknownCaps.syncsProgressRemotely, isFalse);
    expect(unknownCaps.canMutateCatalog, isFalse);
    expect(unknownCaps.canImportLocalFiles, isFalse);
  });

  test('按 sourceKey 路由不因顶层仓库被装饰包装而退回激活源，且 ondeckProvider 与 crossSourceOndeckProvider 共享失效', () async {
    final repoA = FakeLibraryRepository(
      ondeck: <Book>[
        const Book(
          id: 'a-b1',
          seriesId: 'a-s1',
          name: 'Alpha 1',
          pagesCount: 10,
        ).withSource(serverAKey),
      ],
    );
    final repoB = FakeLibraryRepository();
    final dlA = _RecordingDownloadService();
    final dlB = _RecordingDownloadService();

    final registry = SourceRegistry(
      localBundle: makeBundle(
        source: const LocalContentSource(),
        library: FakeLibraryRepository(),
      ),
      remoteBundles: <String, SourceBundle>{
        serverAKey: makeBundle(
          source: remoteSourceOfServer(serverA),
          library: repoA,
          download: dlA,
        ),
        serverBKey: makeBundle(
          source: remoteSourceOfServer(serverB),
          library: repoB,
          download: dlB,
        ),
      },
    );

    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <Override>[
        sourceRegistryProvider.overrideWithValue(registry),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        // 模拟生产侧对顶层 provider 施加装饰器：不得影响按 sourceKey 路由。
        libraryRepositoryProvider.overrideWithValue(FakeLibraryRepository()),
        downloadServiceProvider.overrideWithValue(_RecordingDownloadService()),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(activeSourceProvider.notifier)
        .selectSource(serverBKey);

    expect(
      container.read(libraryRepositoryForSourceProvider(serverAKey)),
      same(repoA),
    );
    expect(
      container.read(downloadServiceForSourceProvider(serverAKey)),
      same(dlA),
    );
    expect(identical(ondeckProvider, crossSourceOndeckProvider), isTrue);

    final first = await container.read(ondeckProvider.future);
    expect(first.items.map((Book b) => b.id), <String>['a-b1']);

    repoA.ondeckFailure = const NetworkFailure();
    container.invalidate(ondeckProvider);
    await expectLater(
      container.read(ondeckProvider.future),
      throwsA(isA<NetworkFailure>()),
    );
  });
}
