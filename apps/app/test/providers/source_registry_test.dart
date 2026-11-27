import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/missing_source_repository.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

import '../support/test_source_overrides.dart';

void main() {
  group('ActiveSourceController 与 SourceRegistry 多源状态流转', () {
    late Directory tempDir;

    setUp(() {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      tempDir = Directory.systemTemp.createTempSync('yomu_source_reg_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    ProviderContainer buildContainer({
      StoredServer? activeServer,
      List<StoredServer>? allServers,
      AppSettings initialSettings = AppSettings.defaults,
      List<Override> extraOverrides = const <Override>[],
    }) {
      final db = ProgressDatabase(NativeDatabase.memory());
      final serverStore = allServers != null
          ? InMemoryServerStore.withAll(allServers, active: activeServer)
          : InMemoryServerStore(activeServer);
      final settingsStore = InMemorySettingsStore(initialSettings);
      final container = ProviderContainer(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(
            LocalComicsStorage(rootResolver: () async => tempDir),
          ),
          serverStoreProvider.overrideWithValue(serverStore),
          settingsStoreProvider.overrideWithValue(settingsStore),
          ...extraOverrides,
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      return container;
    }

    test('全新安装（无服务器、无 activeSourceKey）默认进入本机源', () async {
      final container = buildContainer()..read(activeSourceProvider);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final active = container.read(activeSourceProvider);
      expect(active, isA<LocalContentSource>());
      expect(active.sourceKey, kLocalSourceKey);
      expect(container.read(availableSourcesProvider), hasLength(1));
    });

    test('老用户升级（已存活动 Komga 服务器且无 activeSourceKey）无缝恢复至该服务器源', () async {
      final server = StoredServer(
        address: ServerAddress.parse('https://nas.example.com'),
        apiKey: 'secret-key',
        accountEmail: 'reader@example.com',
      );
      final container = buildContainer(activeServer: server)
        ..read(activeSourceProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final active = container.read(activeSourceProvider);
      expect(active.isCloud, isTrue);
      expect(active.sourceKey, 'https://nas.example.com');
      expect(container.read(availableSourcesProvider), hasLength(2));
    });

    test('已连服务器的用户手动切到本机源后重启，保持停留在树状清晰的本机源且不丢服务器', () async {
      final server = StoredServer(
        address: ServerAddress.parse('https://nas.example.com'),
        apiKey: 'secret-key',
        accountEmail: 'reader@example.com',
      );
      final container = buildContainer(activeServer: server)
        ..read(activeSourceProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await container
          .read(activeSourceProvider.notifier)
          .selectSource(kLocalSourceKey);
      expect(container.read(activeSourceProvider), isA<LocalContentSource>());

      final persisted = await container.read(settingsStoreProvider).load();
      expect(persisted.activeSourceKey, kLocalSourceKey);

      // 模拟重启恢复同一份 settings
      final restarted = buildContainer(
        activeServer: server,
        initialSettings: persisted,
      )..read(activeSourceProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(restarted.read(activeSourceProvider), isA<LocalContentSource>());
      expect(restarted.read(availableSourcesProvider), hasLength(2));
    });

    test('mergeCrossSourceContinueReading 按最后阅读时间跨源排序并保序追加待读下一卷', () async {
      final db = ProgressDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'local:b1',
          seriesTitle: 'Local Manga',
          bookName: 'Vol. 1',
          storageKind: 'zip',
          relativePath: 'b1.cbz',
          sizeBytes: 100,
          pages: <ArchivePageEntry>[
            ArchivePageEntry(
              number: 1,
              entryName: '1.jpg',
              uncompressedSize: 100,
            ),
          ],
        ),
        generateSeriesId: () => 'local:s1',
      );

      final localActive = Book(
        id: 'local:b1',
        seriesId: 'local:s1',
        name: 'Local Vol. 1',
        pagesCount: 20,
        readProgress: ReadProgress(
          page: 5,
          completed: false,
          lastModified: DateTime.utc(2026, 11, 26, 8),
        ),
      );
      final cloudActiveNewer = Book(
        id: 'cloud-b9',
        seriesId: 'cloud-s9',
        name: 'Cloud Vol. 9',
        pagesCount: 30,
        sourceKey: 'https://komga.example.com',
        readProgress: ReadProgress(
          page: 12,
          completed: false,
          lastModified: DateTime.utc(2026, 11, 26, 10),
        ),
      );
      const localUpNext = Book(
        id: 'local:b2',
        seriesId: 'local:s2',
        name: 'Local Next Vol. 2',
        pagesCount: 20,
      );

      final merged = mergeCrossSourceContinueReading(
        <Book>[localActive, localUpNext],
        <Book>[cloudActiveNewer],
      );
      expect(merged.map((b) => b.id), <String>[
        'cloud-b9',
        'local:b1',
        'local:b2',
      ]);
      expect(merged.first.isCloud, isTrue);
      expect(merged[1].isCloud, isFalse);
    });

    test('SourceRegistry 懒加载且增删其他服务器时不销毁已访问服务器的 Bundle 缓存（P1-3）', () async {
      final serverA = StoredServer(
        address: ServerAddress.parse('https://alpha.komga.test'),
        apiKey: 'key-a',
        accountEmail: 'a@test.com',
      );
      final serverB = StoredServer(
        address: ServerAddress.parse('https://beta.komga.test'),
        apiKey: 'key-b',
        accountEmail: 'b@test.com',
      );
      final serverC = StoredServer(
        address: ServerAddress.parse('https://gamma.komga.test'),
        apiKey: 'key-c',
        accountEmail: 'c@test.com',
      );
      final serverStore = InMemoryServerStore.withAll(<StoredServer>[
        serverA,
        serverB,
      ]);
      final db = ProgressDatabase(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(
            LocalComicsStorage(rootResolver: () async => tempDir),
          ),
          serverStoreProvider.overrideWithValue(serverStore),
          settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      await container.read(serverListProvider.future);
      final registry1 = container.read(sourceRegistryProvider);
      expect(registry1.sources, hasLength(3));

      final bundleA1 = registry1.bundleFor(serverA.id);
      expect(bundleA1.source.sourceKey, serverA.id);

      // 新增服务器 C 并刷新列表：服务器 A 的 SourceBundle 与仓库实例必须保持 identical，不被销毁重建。
      await serverStore.save(serverC);
      container.invalidate(serverListProvider);
      await container.read(serverListProvider.future);

      final registry2 = container.read(sourceRegistryProvider);
      expect(registry2.sources, hasLength(4));
      final bundleA2 = registry2.bundleFor(serverA.id);
      expect(identical(bundleA1, bundleA2), isTrue);
      expect(identical(bundleA1.library, bundleA2.library), isTrue);
    });

    test('未知 sourceKey 绝不静默回退本机书库：bundleFor 抛 StateError，scoped provider 返回 MissingSourceRepository（P1-3）', () async {
      const missingKey = 'https://deleted.komga.test';
      final container = buildContainer();
      await container.read(serverListProvider.future);

      final registry = container.read(sourceRegistryProvider);
      expect(registry.bundleOrNull(missingKey), isNull);
      expect(() => registry.bundleFor(missingKey), throwsStateError);

      final repo = container.read(
        libraryRepositoryForSourceProvider(missingKey),
      );
      expect(repo, isA<MissingSourceRepository>());
      expect(await repo.bookCover('any-book'), isNull);
      await expectLater(repo.series(), throwsA(isA<ServerFailure>()));
    });

    test(
      '空 sourceKey 在 registry 与所有 scoped provider 中语义统一为缺失源（P1-1）',
      () async {
        final container = buildContainer();
        await container.read(serverListProvider.future);

        final registry = container.read(sourceRegistryProvider);
        expect(registry.bundleOrNull(''), isNull);
        expect(() => registry.bundleFor(''), throwsStateError);

        expect(
          container.read(sourceCapabilitiesForKeyProvider('')),
          SourceCapabilities.none,
        );
        expect(
          container.read(libraryRepositoryForSourceProvider('')),
          isA<MissingSourceRepository>(),
        );
        expect(
          container.read(readerRepositoryForSourceProvider('')),
          isA<MissingSourceRepository>(),
        );
        expect(
          container.read(collectionsRepositoryForSourceProvider('')),
          isA<MissingSourceRepository>(),
        );
        expect(
          container.read(readStatusRepositoryForSourceProvider('')),
          isA<MissingSourceRepository>(),
        );
      },
    );

    test('activeSourceBundleProvider 远程源未就绪时返回 null，绝不静默回退本机源（P1-3）', () async {
      const remote = RemoteContentSource(
        sourceKey: 'https://pending.komga.test',
        displayName: 'Pending Komga',
      );
      final listCompleter = Completer<List<StoredServer>>();
      final container = buildContainer(
        extraOverrides: <Override>[
          activeSourceProvider.overrideWith(
            () => FixedActiveSourceController(remote),
          ),
          serverListProvider.overrideWith((Ref ref) => listCompleter.future),
        ],
      );

      // 服务器列表仍在加载期间，activeSourceBundleProvider 必须为 null 而非 localBundle。
      expect(container.read(activeSourceBundleProvider), isNull);
      expect(
        container.read(libraryRepositoryProvider),
        isA<MissingSourceRepository>(),
      );
      expect(
        container.read(readerRepositoryProvider),
        isA<MissingSourceRepository>(),
      );
      expect(
        container.read(collectionsRepositoryProvider),
        isA<MissingSourceRepository>(),
      );
      expect(
        container.read(readStatusRepositoryProvider),
        isA<MissingSourceRepository>(),
      );

      // ShelfController 在服务器列表加载期间应停在初始态，不把 Komga 筛选套到本地库，也不抛错。
      final shelf = container.read(shelfProvider);
      expect(shelf.series, isEmpty);
      expect(shelf.failure, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(shelfProvider).failure, isNull);
    });

    test('N8：冷启动持久化 activeSourceKey 未加载完前绝不暴露本机仓库，加载后直切目标远程源', () async {
      final server = StoredServer(
        address: ServerAddress.parse('https://remote.komga.test'),
        apiKey: 'secret-key',
        accountEmail: 'reader@test.com',
      );
      final settingsCompleter = Completer<AppSettings>();
      final delayedStore = _DelayedSettingsStore(settingsCompleter.future);
      final db = ProgressDatabase(NativeDatabase.memory());
      // 往本机库先种入一本漫画，若冷启动误走本机仓库则书架会闪出本机内容。
      await db.insertImportedLocalBook(
        const LocalBookImportDraft(
          bookId: 'local:seed-1',
          seriesTitle: 'Local Flash Trap',
          bookName: 'Vol. 1',
          storageKind: 'zip',
          relativePath: 'trap.cbz',
          sizeBytes: 100,
          pages: <ArchivePageEntry>[
            ArchivePageEntry(
              number: 1,
              entryName: '1.jpg',
              uncompressedSize: 100,
            ),
          ],
        ),
        generateSeriesId: () => 'local:seed-s1',
      );
      final container = ProviderContainer(
        overrides: <Override>[
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(
            LocalComicsStorage(rootResolver: () async => tempDir),
          ),
          serverStoreProvider.overrideWithValue(
            InMemoryServerStore.withAll(<StoredServer>[server]),
          ),
          settingsStoreProvider.overrideWithValue(delayedStore),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      await container.read(serverListProvider.future);
      container.read(activeSourceProvider);

      // settingsStore.load() 尚未返回前：必须处于 restoring 态，绝不返回 LocalLibraryRepository。
      expect(container.read(activeSourceRestoringProvider), isTrue);
      expect(container.read(activeSourceBundleProvider), isNull);
      expect(
        container.read(libraryRepositoryProvider),
        isA<MissingSourceRepository>(),
      );
      final shelfWhileRestoring = container.read(shelfProvider);
      expect(shelfWhileRestoring.series, isEmpty);
      expect(shelfWhileRestoring.failure, isNull);

      // 持久化选择返回远程源后，一步到位切到远程源并解除 restoring 态。
      settingsCompleter.complete(AppSettings(activeSourceKey: server.id));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(container.read(activeSourceRestoringProvider), isFalse);
      expect(container.read(activeSourceProvider).sourceKey, server.id);
      expect(
        container.read(activeSourceBundleProvider)?.source.sourceKey,
        server.id,
      );
    });
  });
}

final class _DelayedSettingsStore extends InMemorySettingsStore {
  _DelayedSettingsStore(this._loadFuture);

  final Future<AppSettings> _loadFuture;

  @override
  Future<AppSettings> load() => _loadFuture;
}
