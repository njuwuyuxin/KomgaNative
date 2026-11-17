import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/connection_screen.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/screens/splash_screen.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';

import '../support/fake_library.dart';
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
  }) async {
    final data = series ?? demoShelf();
    final repository = FakeLibraryRepository(
      series: data,
      libraries: demoLibraries(),
      seriesFailure: failure,
    );

    // 用仓库自己吐出的那份 bytes 预热 ImageCache：key（MemoryImage）与页面里
    // 生成的完全一致，图片才会在第一帧就画出来。
    final covers = <Uint8List>[];
    if (failure == null) {
      for (final s in data) {
        final bytes = await repository.seriesCover(s.id);
        if (bytes != null) covers.add(bytes);
      }
    }

    await pumpGoldenScreen(
      tester,
      screen: const LibraryScreen(),
      size: size,
      theme: theme,
      textScale: textScale,
      overrides: <Override>[
        libraryRepositoryProvider.overrideWithValue(repository),
      ],
      precacheCovers: covers,
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
      precacheCovers: covers,
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

  testWidgets('series@eink', (WidgetTester tester) async {
    await pumpSeriesGolden(
      tester,
      name: 'series@eink',
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
      overrides: memorySession(connected: true),
    );
    await expectGolden(tester, 'settings@eink');
  });

  testWidgets('reader@phone_dark', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const ReaderScreen(bookId: 'b1'),
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
    );
    await expectGolden(tester, 'reader@phone_dark');
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
}
