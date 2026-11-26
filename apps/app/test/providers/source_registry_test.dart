import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/local/local_catalog_write_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

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
    }) {
      final db = ProgressDatabase(NativeDatabase.memory());
      final serverStore = allServers != null
          ? InMemoryServerStore.withAll(allServers, active: activeServer)
          : InMemoryServerStore(activeServer);
      final settingsStore = InMemorySettingsStore(initialSettings);
      final container = ProviderContainer(
        overrides: [
          progressDatabaseProvider.overrideWithValue(db),
          localComicsStorageProvider.overrideWithValue(
            LocalComicsStorage(rootResolver: () async => tempDir),
          ),
          serverStoreProvider.overrideWithValue(serverStore),
          settingsStoreProvider.overrideWithValue(settingsStore),
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
  });
}
