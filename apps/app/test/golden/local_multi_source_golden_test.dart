import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

import '../support/fake_library.dart';
import '../support/fake_reader.dart';
import '../support/fakes.dart';
import 'golden_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  List<Override> buildEmptyLocalOverrides({
    required ProgressDatabase db,
    required HttpCacheDatabase cacheDb,
  }) {
    final emptyLocalBundle = SourceBundle(
      source: const LocalContentSource(),
      library: FakeLibraryRepository(),
      reader: FakeReaderRepository(pageCount: 10),
      collections: FakeLibraryRepository(),
      readStatus: FakeLibraryRepository(),
    );
    return <Override>[
      progressDatabaseProvider.overrideWithValue(db),
      httpCacheDatabaseProvider.overrideWithValue(cacheDb),
      serverStoreProvider.overrideWithValue(InMemoryServerStore()),
      settingsStoreProvider.overrideWithValue(InMemorySettingsStore()),
      sourceRegistryProvider.overrideWithValue(
        SourceRegistry(
          localBundle: emptyLocalBundle,
          remoteBundles: const <String, SourceBundle>{},
        ),
      ),
    ];
  }

  List<Override> buildMultiSourceOverrides({
    required ProgressDatabase db,
    required HttpCacheDatabase cacheDb,
  }) {
    final server = storedServer();
    final cloudItems = <Series>[
      for (final item in demoShelf()) item.withSource(server.id),
    ];
    final localBundle = SourceBundle(
      source: const LocalContentSource(),
      library: FakeLibraryRepository(series: demoShelf()),
      reader: FakeReaderRepository(pageCount: 10),
      collections: FakeLibraryRepository(),
      readStatus: FakeLibraryRepository(),
    );
    final remoteBundle = SourceBundle(
      source: RemoteContentSource(
        sourceKey: server.id,
        displayName: 'Home NAS',
      ),
      library: FakeLibraryRepository(
        series: cloudItems,
        libraries: demoLibraries(),
      ),
      reader: FakeReaderRepository(pageCount: 10),
      collections: FakeLibraryRepository(),
      readStatus: FakeLibraryRepository(),
    );
    return <Override>[
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
    ];
  }

  group('本地空书架引导黄金图（单源隐形 + 导入圆球）', () {
    for (final (String suffix, Size size, ThemeData theme)
        in <(String, Size, ThemeData)>[
          ('phone_light', GoldenSizes.phone, AppTheme.light()),
          ('tablet_dark', GoldenSizes.tablet, AppTheme.dark()),
          ('eink', GoldenSizes.eink, AppTheme.eink()),
        ]) {
      testWidgets('library_local_empty@$suffix', (WidgetTester tester) async {
        final db = ProgressDatabase(NativeDatabase.memory());
        final cacheDb = HttpCacheDatabase(NativeDatabase.memory());
        addTearDown(() async {
          await db.close();
          await cacheDb.close();
        });

        await pumpGoldenScreen(
          tester,
          screen: const LibraryScreen(),
          size: size,
          theme: theme,
          overrides: buildEmptyLocalOverrides(db: db, cacheDb: cacheDb),
        );
        await expectGolden(tester, 'library_local_empty@$suffix');
      });
    }
  });

  group('多源分组切换栏与云端系列微标黄金图', () {
    for (final (String suffix, Size size, ThemeData theme)
        in <(String, Size, ThemeData)>[
          ('phone_light', GoldenSizes.phone, AppTheme.light()),
          ('tablet_dark', GoldenSizes.tablet, AppTheme.dark()),
          ('eink', GoldenSizes.eink, AppTheme.eink()),
        ]) {
      testWidgets('library_multi_source@$suffix', (WidgetTester tester) async {
        final db = ProgressDatabase(NativeDatabase.memory());
        final cacheDb = HttpCacheDatabase(NativeDatabase.memory());
        addTearDown(() async {
          await db.close();
          await cacheDb.close();
        });

        await pumpGoldenScreen(
          tester,
          screen: const LibraryScreen(),
          size: size,
          theme: theme,
          overrides: buildMultiSourceOverrides(db: db, cacheDb: cacheDb),
        );
        await expectGolden(tester, 'library_multi_source@$suffix');
      });
    }
  });
}
