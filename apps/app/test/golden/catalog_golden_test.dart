import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/settings_store.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/screens/collection_detail_screen.dart';
import 'package:yomu/src/screens/collections_screen.dart';
import 'package:yomu/src/screens/readlist_detail_screen.dart';
import 'package:yomu/src/screens/search_screen.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

import '../support/fake_library.dart';
import '../support/test_source_overrides.dart';
import 'golden_harness.dart';

/// 编目与浏览页 UI 基线矩阵（系列详情、收藏集/阅读列表、搜索）。
void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpSeriesGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    bool empty = false,
  }) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
    );
    if (empty) repository.bookCount = 0;

    final covers = <Uint8List>[];
    final seriesCover = await repository.seriesCover('s1');
    if (seriesCover != null) covers.add(seriesCover);
    for (var i = 1; i <= repository.bookCount; i++) {
      final bytes = await repository.bookCover('s1-b$i');
      if (bytes != null) covers.add(bytes);
    }

    await pumpGoldenScreen(
      tester,
      screen: const SeriesDetailScreen(seriesId: 's1'),
      size: size,
      theme: theme,
      overrides: <Override>[
        ...testSourceOverrides(library: repository),
        // 书行里的下载按钮会读"待恢复的下载队列"：给内存库，
        // 否则测试会去开真实的 sqlite（path_provider 没有平台通道）。
        httpCacheDatabaseProvider.overrideWithValue(
          HttpCacheDatabase(NativeDatabase.memory()),
        ),
      ],
      precacheImages: covers,
    );
    await expectGolden(tester, name);
  }

  testWidgets('series@phone_light', (WidgetTester tester) async {
    await pumpSeriesGolden(
      tester,
      name: 'series@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('series@tablet_dark', (WidgetTester tester) async {
    await pumpSeriesGolden(
      tester,
      name: 'series@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  /// 宽屏两栏：左头部 / 右书列表。1024 宽正好落在 `WindowSizeClass.expanded`。
  testWidgets('series@tablet_two_pane', (WidgetTester tester) async {
    await pumpSeriesGolden(
      tester,
      name: 'series@tablet_two_pane',
      size: GoldenSizes.tablet,
      theme: AppTheme.light(),
    );
  });

  testWidgets('series@eink', (WidgetTester tester) async {
    await pumpSeriesGolden(
      tester,
      name: 'series@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  /// 首次打开（元信息与书列表都还没回来）：头部封面/Hero 落点必须在，
  /// 其余字段与书列表用骨架占位。这条基线钉住"首次打开与后续打开视觉一致"。
  ///
  /// 不能用 `pumpAndSettle`：骨架的微光是无限循环动画。多推一段（> 一屏的
  /// 淡入时长）让列表区的 `PhaseFade` 到终值、封面 Provider 换进真图。
  Future<void> pumpSeriesLoadingGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
  }) async {
    final repository =
        FakeLibraryRepository(series: demoShelf(), libraries: demoLibraries())
          ..detailGate = Completer<void>()
          ..booksGate = Completer<void>();

    final covers = <Uint8List>[];
    final seriesCover = await repository.seriesCover('s1');
    if (seriesCover != null) covers.add(seriesCover);

    await pumpGoldenScreen(
      tester,
      screen: const SeriesDetailScreen(seriesId: 's1'),
      size: size,
      theme: theme,
      overrides: <Override>[...testSourceOverrides(library: repository)],
      precacheImages: covers,
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectGolden(tester, name);
  }

  testWidgets('series_loading@phone_light', (WidgetTester tester) async {
    await pumpSeriesLoadingGolden(
      tester,
      name: 'series_loading@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('series_loading@tablet_two_pane', (WidgetTester tester) async {
    await pumpSeriesLoadingGolden(
      tester,
      name: 'series_loading@tablet_two_pane',
      size: GoldenSizes.tablet,
      theme: AppTheme.light(),
    );
  });

  testWidgets('series_loading@eink', (WidgetTester tester) async {
    await pumpSeriesLoadingGolden(
      tester,
      name: 'series_loading@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  Future<void> pumpCollectionDetailGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
  }) async {
    final series = demoShelf();
    final library = FakeLibraryRepository(series: series);
    final covers = <Uint8List>[];
    for (final s in series.take(2)) {
      final bytes = await library.seriesCover(s.id);
      if (bytes != null) covers.add(bytes);
    }
    await pumpGoldenScreen(
      tester,
      screen: const CollectionDetailScreen(
        collectionId: 'c1',
        title: 'Reading order',
      ),
      size: size,
      theme: theme,
      overrides: <Override>[...testSourceOverrides(library: library)],
      precacheImages: covers,
      realTimeSettle: true,
    );
    await expectGolden(tester, name);
  }

  testWidgets('collection_detail@phone_light', (WidgetTester tester) async {
    await pumpCollectionDetailGolden(
      tester,
      name: 'collection_detail@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('collection_detail@tablet_dark', (WidgetTester tester) async {
    await pumpCollectionDetailGolden(
      tester,
      name: 'collection_detail@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('collection_detail@eink', (WidgetTester tester) async {
    await pumpCollectionDetailGolden(
      tester,
      name: 'collection_detail@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  Future<void> pumpReadListGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
  }) async {
    final library = FakeLibraryRepository(ondeck: demoOndeck());
    final covers = <Uint8List>[];
    for (final b in demoOndeck()) {
      final bytes = await library.bookCover(b.id);
      if (bytes != null) covers.add(bytes);
    }
    await pumpGoldenScreen(
      tester,
      screen: const ReadListDetailScreen(
        readListId: 'r1',
        title: 'Weekend reading',
      ),
      size: size,
      theme: theme,
      overrides: <Override>[
        ...testSourceOverrides(library: library),
        // 书行的下载按钮会读待恢复队列：给内存库，别去开真实 sqlite。
        httpCacheDatabaseProvider.overrideWithValue(
          HttpCacheDatabase(NativeDatabase.memory()),
        ),
      ],
      precacheImages: covers,
      realTimeSettle: true,
    );
    await expectGolden(tester, name);
  }

  testWidgets('readlist_detail@phone_light', (WidgetTester tester) async {
    await pumpReadListGolden(
      tester,
      name: 'readlist_detail@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('readlist_detail@tablet_dark', (WidgetTester tester) async {
    await pumpReadListGolden(
      tester,
      name: 'readlist_detail@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('readlist_detail@eink', (WidgetTester tester) async {
    await pumpReadListGolden(
      tester,
      name: 'readlist_detail@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  Future<void> pumpSearchGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    List<String> history = const <String>[],
    String? query,
  }) async {
    await pumpGoldenScreen(
      tester,
      screen: const SearchScreen(),
      size: size,
      theme: theme,
      overrides: <Override>[
        ...testSourceOverrides(
          library: FakeLibraryRepository(series: demoShelf()),
        ),
        if (history.isNotEmpty)
          settingsStoreProvider.overrideWithValue(
            InMemorySettingsStore(
              const AppSettings().copyWith(searchHistory: history),
            ),
          ),
      ],
    );
    if (query != null) {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }
    await expectGolden(tester, name);
  }

  /// 搜索历史态（SCH-01）：最近搜索列表 + 清空 + 单条删除。
  testWidgets('search_history@phone_light', (WidgetTester tester) async {
    await pumpSearchGolden(
      tester,
      name: 'search_history@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      history: <String>['vagabond', 'frieren', 'akira'],
    );
  });

  testWidgets('search@phone_light', (WidgetTester tester) async {
    await pumpSearchGolden(
      tester,
      name: 'search@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('search@tablet_dark', (WidgetTester tester) async {
    await pumpSearchGolden(
      tester,
      name: 'search@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('search@eink', (WidgetTester tester) async {
    await pumpSearchGolden(
      tester,
      name: 'search@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  Future<void> pumpCollectionsGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
  }) async {
    final data = demoShelf();
    final repository = FakeLibraryRepository(series: data);
    final covers = <Uint8List>[];
    for (final s in data) {
      final bytes = await repository.seriesCover(s.id);
      if (bytes != null) covers.add(bytes);
    }
    await pumpGoldenScreen(
      tester,
      screen: const CollectionsScreen(),
      size: size,
      theme: theme,
      precacheImages: covers,
      overrides: <Override>[...testSourceOverrides(library: repository)],
    );
    await expectGolden(tester, name);
  }

  testWidgets('collections@phone_light', (WidgetTester tester) async {
    await pumpCollectionsGolden(
      tester,
      name: 'collections@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('collections@tablet_dark', (WidgetTester tester) async {
    await pumpCollectionsGolden(
      tester,
      name: 'collections@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('collections@eink', (WidgetTester tester) async {
    await pumpCollectionsGolden(
      tester,
      name: 'collections@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });
}
