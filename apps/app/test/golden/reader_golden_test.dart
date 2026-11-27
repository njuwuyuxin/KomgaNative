import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reader_prefs_store.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_reader/yomu_reader.dart';
import 'package:yomu_sync/yomu_sync.dart';

import '../support/fake_library.dart';
import '../support/fake_reader.dart';
import '../support/fakes.dart';
import '../support/test_source_overrides.dart';
import 'golden_harness.dart';

/// 阅读器与阅读设置 UI 基线矩阵。
void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpReaderGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    String bookId = 'b1',
    Book? book,
    FakeReaderRepository? repository,
    FakeLibraryRepository? library,
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
        ...testSourceOverrides(library: library, reader: reader),
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
        imageSaverProvider.overrideWithValue(FakeImageSaver()),
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
    await tester.tap(find.byKey(const Key('reader-more-button')));
    await tester.pumpAndSettle();
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

  testWidgets('reader@phone_light', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('reader@tablet_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader@tablet_dark',
      size: GoldenSizes.tablet,
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

  testWidgets('reader_auto_eink', (WidgetTester tester) async {
    // 只靠自动探测（不打开"强制墨水屏"）也必须整屏走墨水屏：
    // 白底、瞬切、无动态背景。FIX-01 之前这里画出来是黑底。
    await pumpReaderGolden(
      tester,
      name: 'reader_auto_eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      extraOverrides: <Override>[
        einkDetectedProvider.overrideWith((ref) async => true),
      ],
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
      prefs: const ReaderPrefs(
        global: ReaderConfig(background: ReaderBackgroundChoice.dynamic),
      ),
    );
  });

  testWidgets('reader_immersive@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_immersive@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      repository: FakeReaderRepository(pageNames: const <String>['edge_split']),
      prefs: const ReaderPrefs(
        global: ReaderConfig(background: ReaderBackgroundChoice.immersive),
      ),
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
      prefs: const ReaderPrefs(global: ReaderConfig(trimBorders: true)),
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
      library: library,
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
        await t.tap(find.byKey(const Key('reader-more-button')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('reader-pages-button')));
        await t.pumpAndSettle();
      },
    );
  });

  testWidgets('reader_quick_settings@phone_dark', (WidgetTester tester) async {
    // RDR-03：顶栏 AA 打开的快捷设置（亮度/背景/方向/适配/锁定缩放）。
    await pumpReaderGolden(
      tester,
      name: 'reader_quick_settings@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('reader-quick-settings-button')));
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
        await t.tap(find.byKey(const Key('reader-more-button')));
        await t.pumpAndSettle();
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
            config: ReaderConfig(mode: ReaderModeChoice.double),
          ),
          ReaderPreset(
            id: 'p2',
            name: 'Webtoon',
            config: ReaderConfig(mode: ReaderModeChoice.vertical),
          ),
        ],
      ),
      act: (WidgetTester t) async {
        await t.tap(find.byKey(const Key('reader-more-button')));
        await t.pumpAndSettle();
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
        await t.tap(find.byKey(const Key('reader-more-button')));
        await t.pumpAndSettle();
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
        await t.tap(find.byKey(const Key('reader-more-button')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('reader-settings-button')));
      },
    );
  });
}
