import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/drift_http_cache.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/download/download_service.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/reader_prefs_store.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/collections_screen.dart';
import 'package:komga_native/src/screens/collection_detail_screen.dart';
import 'package:komga_native/src/screens/connection_screen.dart';
import 'package:komga_native/src/screens/downloads_screen.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/readlist_detail_screen.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/reading_now_screen.dart';
import 'package:komga_native/src/screens/search_screen.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/screens/splash_screen.dart';
import 'package:komga_native/src/session/certificate_prompt.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/certificate_panel.dart';
import 'package:komga_native/src/widgets/floating_nav_bar.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

import '../support/fake_library.dart';
import '../support/fake_reader.dart';
import '../support/fakes.dart';
import 'golden_harness.dart';

/// UI 基线矩阵。
///
/// 覆盖三件事：形态（手机/平板/墨水屏）、主题（light/dark/eink）、文本缩放。
/// 书架走真实 Repository 接口 + 假数据（含真实 PNG 封面），因此不联网但版式真实。
void main() {
  setUpAll(loadAppFonts);

  /// 依赖会话的页面统一注入内存实现，避免钥匙串通道缺失把错误渲染进基线。
  List<Override> memorySession({bool connected = false}) => <Override>[
    serverStoreProvider.overrideWithValue(
      InMemoryServerStore(connected ? storedServer() : null),
    ),
  ];

  Future<void> pumpShelfGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    double textScale = 1.0,
    List<Series>? series,
    ShelfFailure? failure,
    bool offline = false,
    List<Book>? ondeck,
    bool withNavBar = false,
    Future<void> Function(WidgetTester tester)? act,
  }) async {
    final data = series ?? demoShelf();
    // 正常书架给两本"继续阅读"；空态/错误态不给（那一行本来就不该出现）。
    final continueBooks =
        ondeck ??
        (failure == null && data.isNotEmpty ? demoOndeck() : const <Book>[]);
    final repository = FakeLibraryRepository(
      series: data,
      libraries: demoLibraries(),
      seriesFailure: failure,
      ondeck: continueBooks,
    );

    // 用仓库自己吐出的那份 bytes 预热 ImageCache：key（MemoryImage）与页面里
    // 生成的完全一致，图片才会在第一帧就画出来。
    final covers = <Uint8List>[];
    if (failure == null) {
      for (final s in data) {
        final bytes = await repository.seriesCover(s.id);
        if (bytes != null) covers.add(bytes);
      }
      for (final b in continueBooks) {
        final bytes = await repository.bookCover(b.id);
        if (bytes != null) covers.add(bytes);
      }
    }

    // 离线提示由缓存实例广播：必须在首帧之前报告，基线才画得出来。
    final cache = DriftHttpCache(HttpCacheDatabase(NativeDatabase.memory()));
    if (offline) cache.reportOffline('https://komga.example.com');

    await pumpGoldenScreen(
      tester,
      screen: withNavBar
          ? const _WithFloatingNavBar(child: LibraryScreen())
          : const LibraryScreen(),
      size: size,
      theme: theme,
      textScale: textScale,
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(repository),
        httpCacheProvider.overrideWithValue(cache),
      ],
      precacheImages: covers,
      act: act,
    );
    await expectGolden(tester, name);
  }

  testWidgets('library@phone_light', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  /// 真实首页形态：书架 + 底部悬浮玻璃导航条。
  ///
  /// 页面基线本身不带外壳（外壳在 `AdaptiveShell` 里），这一张专门钉住
  /// "玻璃压在封面上"的观感，以及内容底部为浮层留出的空白。
  testWidgets('library_nav@phone_light', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_nav@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      withNavBar: true,
    );
  });

  testWidgets('library@tablet_dark', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('library@phone_light_text1.3', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library@phone_light_text1.3',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      textScale: 1.3,
    );
  });

  testWidgets('library@eink', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  testWidgets('library_offline@phone_light', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_offline@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      offline: true,
    );
  });

  testWidgets('library_sort_menu@phone_light', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_sort_menu@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('shelf-sort-menu')));
        await t.pumpAndSettle();
      },
    );
  });

  /// 列表视图（UI-P2-7）：与网格共用同一份数据，只换 sliver 类型。
  /// 这是一套独立版式（横向封面行），必须有基线，不能只靠 widget 测试。
  testWidgets('library_list@phone_light', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_list@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('shelf-view-menu')));
        await t.pumpAndSettle();
        await t.tap(find.text('List'));
        await t.pumpAndSettle();
      },
    );
  });

  /// 长按上下文菜单（UI-P2-5）：缩放弹出层也是新 UI，单独出一张基线。
  testWidgets('library_context_menu@phone_light', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_context_menu@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      act: (WidgetTester t) async {
        await t.longPress(find.byKey(const Key('series-s1')));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('library_empty@phone_light', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_empty@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      series: const <Series>[],
    );
  });

  testWidgets('library_error@eink', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_error@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      failure: const NetworkFailure(),
    );
  });

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
        libraryRepositoryProvider.overrideWithValue(repository),
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
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(repository),
      ],
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

  /// "正在读"首页（UI-P2-6）：继续阅读卡片 + 最近添加 + 按库分组三条货架。
  Future<void> pumpReadingNowGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
  }) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
      ondeck: demoOndeck(),
    );
    // 封面预热：与页面里同一份 bytes 实例，ImageCache 才能命中。
    final covers = <Uint8List>[];
    for (final book in demoOndeck()) {
      final bytes = await repository.bookCover(book.id);
      if (bytes != null) covers.add(bytes);
    }
    for (final series in demoShelf()) {
      final bytes = await repository.seriesCover(series.id);
      if (bytes != null) covers.add(bytes);
    }
    await pumpGoldenScreen(
      tester,
      screen: const ReadingNowScreen(),
      size: size,
      theme: theme,
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(repository),
      ],
      precacheImages: covers,
      realTimeSettle: true,
    );
    await expectGolden(tester, name);
  }

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
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(library),
      ],
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
        libraryRepositoryProvider.overrideWithValue(library),
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
  }) async {
    await pumpGoldenScreen(
      tester,
      screen: const SearchScreen(),
      size: size,
      theme: theme,
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(
          FakeLibraryRepository(series: demoShelf()),
        ),
      ],
    );
    await expectGolden(tester, name);
  }

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
    await pumpGoldenScreen(
      tester,
      screen: const CollectionsScreen(),
      size: size,
      theme: theme,
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(
          FakeLibraryRepository(series: demoShelf()),
        ),
      ],
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

  Future<void> pumpDownloadsGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
  }) async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    await db.markDownloaded(
      bookId: 's1-b1',
      seriesId: 's1',
      pageCount: 12,
      bytes: 2 * 1024 * 1024,
    );
    final library = FakeLibraryRepository(ondeck: demoOndeck());
    final cover = await library.bookCover('s1-b1');
    await pumpGoldenScreen(
      tester,
      screen: const DownloadsScreen(),
      size: size,
      theme: theme,
      overrides: <Override>[
        httpCacheDatabaseProvider.overrideWithValue(db),
        downloadServiceProvider.overrideWithValue(_GoldenDownloadService()),
        libraryRepositoryProvider.overrideWithValue(library),
      ],
      precacheImages: <Uint8List>[if (cover != null) cover],
      realTimeSettle: true,
    );
    await expectGolden(tester, name);
  }

  testWidgets('downloads@phone_light', (WidgetTester tester) async {
    await pumpDownloadsGolden(
      tester,
      name: 'downloads@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('downloads@tablet_dark', (WidgetTester tester) async {
    await pumpDownloadsGolden(
      tester,
      name: 'downloads@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('downloads@eink', (WidgetTester tester) async {
    await pumpDownloadsGolden(
      tester,
      name: 'downloads@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  testWidgets('reading_now@phone_light', (WidgetTester tester) async {
    await pumpReadingNowGolden(
      tester,
      name: 'reading_now@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('reading_now@tablet_dark', (WidgetTester tester) async {
    await pumpReadingNowGolden(
      tester,
      name: 'reading_now@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('reading_now@eink', (WidgetTester tester) async {
    await pumpReadingNowGolden(
      tester,
      name: 'reading_now@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  testWidgets('settings@eink', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const SettingsScreen(),
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      overrides: <Override>[
        ...memorySession(connected: true),
        // 设置页会读缓存/下载占用：换成内存库，避免 path_provider 平台通道，
        // 也让"Nothing cached yet"成为确定值（否则基线随本机缓存漂移）。
        httpCacheDatabaseProvider.overrideWithValue(
          HttpCacheDatabase(NativeDatabase.memory()),
        ),
      ],
    );
    await expectGolden(tester, 'settings@eink');
  });

  Future<void> pumpReaderGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    String bookId = 'b1',
    Book? book,
    FakeReaderRepository? repository,
    ReaderPrefs? prefs,
    List<Override> extraOverrides = const <Override>[],
    List<Uint8List> extraImages = const <Uint8List>[],
    List<int> precachePages = const <int>[1],
    bool settleAfterActWithRealTime = false,
    Future<void> Function(WidgetTester tester)? act,
    bool forceEink = false,
  }) async {
    final reader = repository ?? FakeReaderRepository();
    final pageBytes = <Uint8List>[...extraImages];
    for (final page in precachePages) {
      final bytes = await reader.warmPage(page);
      if (bytes != null) pageBytes.add(bytes);
    }

    await pumpGoldenScreen(
      tester,
      screen: ReaderScreen(bookId: bookId, book: book ?? demoReaderBook()),
      size: size,
      theme: theme,
      overrides: <Override>[
        readerRepositoryProvider.overrideWithValue(reader),
        // 设置面板会写偏好：黄金图里必须换成内存实现，否则会打真钥匙串通道。
        readerPrefsStoreProvider.overrideWithValue(
          InMemoryReaderPrefsStore(prefs),
        ),
        // 翻页动画会跨过 600ms 的进度防抖，真实现会去开 sqlite（path_provider
        // 在测试里没有通道）。换成内存 store，基线不依赖本机文件系统。
        progressSyncProvider.overrideWithValue(
          ProgressSyncService(
            store: InMemoryProgressStore(),
            upload: (ProgressTarget target) async {},
          ),
        ),
        wakeLockProvider.overrideWithValue(FakeWakeLock()),
        // 阅读器配色跟着 settings.forceEink 走，与 AppTheme 必须成对换；
        // 只换主题的话基线会画成黑底（踩过一次）。
        if (forceEink) settingsProvider.overrideWith(EinkSettings.new),
        ...extraOverrides,
      ],
      precacheImages: pageBytes,
      // 底栏的缩略图滑条用 `cacheWidth` 解码，是真实异步解码：假时钟推不动，
      // 不放一段真实时间的话基线里滑条是空的。
      realTimeSettle: true,
      settleAfterActWithRealTime: settleAfterActWithRealTime,
      act: act,
    );
    await expectGolden(tester, name);
  }

  /// 顶栏按钮 → 设置面板 → 选中某项 → 关掉面板。
  Future<void> pickMode(WidgetTester tester, ReadingMode mode) async {
    final choice = switch (mode) {
      ReadingMode.paged => ReaderModeChoice.single,
      ReadingMode.doublePage => ReaderModeChoice.double,
      ReadingMode.verticalScroll => ReaderModeChoice.vertical,
    };
    await tester.tap(find.byKey(const Key('reader-settings-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('reader-mode-${choice.name}')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
  }

  testWidgets('reader@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('reader@eink', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      forceEink: true,
    );
  });

  testWidgets('reader_double@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_double@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      precachePages: <int>[2, 3],
      act: (WidgetTester t) async {
        await pickMode(t, ReadingMode.doublePage);
        final rect = t.getRect(find.byKey(const Key('reader-tap-layer')));
        await t.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
      },
    );
  });

  testWidgets('reader_double@eink', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_double@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      forceEink: true,
      precachePages: <int>[2, 3],
      act: (WidgetTester t) async {
        await pickMode(t, ReadingMode.doublePage);
        final rect = t.getRect(find.byKey(const Key('reader-tap-layer')));
        await t.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
      },
    );
  });

  testWidgets('reader_vertical@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_vertical@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      precachePages: <int>[1, 2],
      act: (WidgetTester t) => pickMode(t, ReadingMode.verticalScroll),
    );
  });

  /// 动态背景（UI-P1-5）：页边是青绿色的合成页，底色应该跟着变成青绿而不是黑色。
  testWidgets('reader_dynamic@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_dynamic@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      repository: FakeReaderRepository(pageNames: const <String>['edge_teal']),
      prefs: const ReaderPrefs(background: ReaderBackgroundChoice.dynamic),
    );
  });

  testWidgets('reader_immersive@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_immersive@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      repository: FakeReaderRepository(pageNames: const <String>['edge_split']),
      prefs: const ReaderPrefs(background: ReaderBackgroundChoice.immersive),
      settleAfterActWithRealTime: true,
    );
  });

  testWidgets('reader_trim@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_trim@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      repository: FakeReaderRepository(
        pageNames: const <String>['trim_border'],
      ),
      prefs: const ReaderPrefs(trimBorders: true),
      settleAfterActWithRealTime: true,
    );
  });

  testWidgets('reader_finished@phone_dark', (WidgetTester tester) async {
    // 书末卡片要展示下一本的封面，所以这一张接管了书列表：书 id 必须是
    // 系列里真实存在的（`nextBookProvider` 按 id 找下一条）。
    final library = FakeLibraryRepository(series: demoShelf());
    final nextCover = await library.bookCover('s1-b2');
    await pumpReaderGolden(
      tester,
      name: 'reader_finished@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      bookId: 's1-b1',
      book: const Book(
        id: 's1-b1',
        seriesId: 's1',
        name: 'Vol. 1',
        number: '1',
        pagesCount: 3,
      ),
      extraOverrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(library),
      ],
      extraImages: <Uint8List>[if (nextCover != null) nextCover],
      precachePages: <int>[1, 2, 3],
      act: (WidgetTester t) async {
        for (var i = 0; i < 2; i++) {
          final rect = t.getRect(find.byKey(const Key('reader-tap-layer')));
          await t.tapAt(Offset(rect.right - rect.width * 0.05, rect.center.dy));
          await t.pumpAndSettle();
        }
      },
    );
  });

  testWidgets('reader_pages@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_pages@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      precachePages: <int>[1, 2, 3],
      // 缩略图用 cacheWidth 解码，属于真实异步解码：假时钟推不动，必须放一段
      // 真实时间再截屏（否则缩略图全是黑块）。
      settleAfterActWithRealTime: true,
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('reader-pages-button')));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('reader_settings@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_settings@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('reader-settings-button')));
      },
    );
  });

  testWidgets('reader_settings_presets@phone_dark', (
    WidgetTester tester,
  ) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_settings_presets@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      prefs: const ReaderPrefs(
        presets: <ReaderPreset>[
          ReaderPreset(
            id: 'p1',
            name: 'Manga',
            prefs: ReaderPrefs(mode: ReaderModeChoice.double),
          ),
          ReaderPreset(
            id: 'p2',
            name: 'Webtoon',
            prefs: ReaderPrefs(mode: ReaderModeChoice.vertical),
          ),
        ],
      ),
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('reader-settings-button')));
      },
    );
  });

  testWidgets('reader_settings@phone_light', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_settings@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('reader-settings-button')));
      },
    );
  });

  testWidgets('reader_settings@eink', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_settings@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      forceEink: true,
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('reader-settings-button')));
      },
    );
  });

  testWidgets('connection@phone_light', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const ConnectionScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      overrides: memorySession(),
    );
    await expectGolden(tester, 'connection@phone_light');
  });

  // 中文基线：验证测试字体子集生效（汉字不是占位方块）。
  testWidgets('connection@phone_light_zh', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const ConnectionScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      locale: const Locale('zh'),
      overrides: memorySession(),
    );
    await expectGolden(tester, 'connection@phone_light_zh');
  });

  testWidgets('connection@eink', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const ConnectionScreen(),
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      overrides: memorySession(),
    );
    await expectGolden(tester, 'connection@eink');
  });

  testWidgets('splash@phone_light', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const SplashScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      settle: false,
    );
    await expectGolden(tester, 'splash@phone_light');
  });

  /// 证书面板：三形态各一张。这是用户唯一能核对指纹的地方，
  /// 墨水屏上如果挤成一团/被裁掉，就等于没法判断。
  Widget certificateProbe() => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: CertificatePanel(
          certificate: CertificatePrompt(
            commonName: '*.yasai.site',
            issuerName: 'E7',
            fingerprint: '74:F8:1F:E1:67:D9:9B:4C',
            selfSigned: false,
            expiresAt: DateTime.utc(2026, 7, 19),
          ),
          onTrust: () {},
          onCancel: () {},
        ),
      ),
    ),
  );

  Future<void> pumpCertificateGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    double textScale = 1.0,
  }) async {
    await pumpGoldenScreen(
      tester,
      screen: certificateProbe(),
      size: size,
      theme: theme,
      textScale: textScale,
    );
    await expectGolden(tester, name);
  }

  testWidgets('certificate@phone_light', (WidgetTester tester) async {
    await pumpCertificateGolden(
      tester,
      name: 'certificate@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('certificate@tablet_dark', (WidgetTester tester) async {
    await pumpCertificateGolden(
      tester,
      name: 'certificate@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('certificate@eink', (WidgetTester tester) async {
    await pumpCertificateGolden(
      tester,
      name: 'certificate@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      textScale: 1.3,
    );
  });
}

/// 模拟 `AdaptiveShell` 的手机形态：内容铺到屏幕底 + 浮动玻璃导航条。
///
/// 这里不建整条路由（`StatefulShellRoute` 在黄金图里没有意义），只要外壳的
/// 关键几何：`extendBody` + 导航条自己带安全区、左右与底部留白。
class _WithFloatingNavBar extends StatelessWidget {
  const _WithFloatingNavBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: FloatingNavBar(
        tabs: const <GlassNavDestination>[
          GlassNavDestination(
            icon: Icons.auto_stories_outlined,
            selectedIcon: Icons.auto_stories,
            label: 'Reading',
          ),
          GlassNavDestination(
            icon: Icons.grid_view_outlined,
            selectedIcon: Icons.grid_view,
            label: 'Library',
          ),
          GlassNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: 'Settings',
          ),
        ],
        selectedTab: 1,
        onTabSelected: (_) {},
        search: const GlassNavDestination(icon: Icons.search, label: 'Search'),
        onSearch: () {},
      ),
    );
  }
}

/// 黄金图用的下载服务：不会真的跑下载，只负责让"已下载"查询返回 null。
class _GoldenDownloadService implements DownloadService {
  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async => false;

  @override
  void cancel(String bookId) {}

  @override
  Future<void> delete(Book book) async {}
}
