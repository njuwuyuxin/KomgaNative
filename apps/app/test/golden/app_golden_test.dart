import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/drift_http_cache.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/reader_prefs_store.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/connection_screen.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/screens/splash_screen.dart';
import 'package:komga_native/src/session/certificate_prompt.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/certificate_panel.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';

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
      screen: const LibraryScreen(),
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
    List<int> precachePages = const <int>[1],
    bool settleAfterActWithRealTime = false,
    Future<void> Function(WidgetTester tester)? act,
    bool forceEink = false,
  }) async {
    final repository = FakeReaderRepository();
    final pageBytes = <Uint8List>[];
    for (final page in precachePages) {
      final bytes = await repository.warmPage(page);
      if (bytes != null) pageBytes.add(bytes);
    }

    await pumpGoldenScreen(
      tester,
      screen: ReaderScreen(bookId: 'b1', book: demoReaderBook()),
      size: size,
      theme: theme,
      overrides: <Override>[
        readerRepositoryProvider.overrideWithValue(repository),
        // 设置面板会写偏好：黄金图里必须换成内存实现，否则会打真钥匙串通道。
        readerPrefsStoreProvider.overrideWithValue(InMemoryReaderPrefsStore()),
        wakeLockProvider.overrideWithValue(FakeWakeLock()),
        // 阅读器配色跟着 settings.forceEink 走，与 AppTheme 必须成对换；
        // 只换主题的话基线会画成黑底（踩过一次）。
        if (forceEink) settingsProvider.overrideWith(EinkSettings.new),
      ],
      precacheImages: pageBytes,
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

  testWidgets('reader_finished@phone_dark', (WidgetTester tester) async {
    await pumpReaderGolden(
      tester,
      name: 'reader_finished@phone_dark',
      size: GoldenSizes.phone,
      theme: AppTheme.dark(),
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
