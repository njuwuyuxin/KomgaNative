import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/screens/connection_screen.dart';
import 'package:yomu/src/screens/downloads_screen.dart';
import 'package:yomu/src/screens/insights_screen.dart';
import 'package:yomu/src/screens/reading_now_screen.dart';
import 'package:yomu/src/screens/settings_screen.dart';
import 'package:yomu/src/screens/splash_screen.dart';
import 'package:yomu/src/session/certificate_prompt.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu/src/widgets/certificate_panel.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

import '../support/fake_library.dart';
import '../support/fakes.dart';
import '../support/test_source_overrides.dart';
import 'golden_harness.dart';

/// 通用页面 UI 基线矩阵（正在读、下载、阅读统计、设置、连接、启动页、证书面板）。
///
/// 其余域已按模块拆分至 `shelf_golden_test.dart`、`catalog_golden_test.dart`
/// 与 `reader_golden_test.dart`，以便 `flutter test` 多进程并行执行。
void main() {
  setUpAll(loadAppFonts);

  /// 依赖会话的页面统一注入内存实现，避免钥匙串通道缺失把错误渲染进基线。
  List<Override> memorySession({bool connected = false}) => <Override>[
    serverStoreProvider.overrideWithValue(
      InMemoryServerStore(connected ? storedServer() : null),
    ),
  ];

  /// "正在读"首页（UI-P2-6）：继续阅读卡片 + 最近添加 + 按库分组三条货架。
  Future<void> pumpReadingNowGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    bool loading = false,
  }) async {
    final repository = FakeLibraryRepository(
      series: demoShelf(),
      libraries: demoLibraries(),
      ondeck: demoOndeck(),
    );
    if (loading) {
      // 卡住 ondeck 与货架，把页面停在"骨架"这一态（FIX-05）。
      repository
        ..ondeckGate = Completer<void>()
        ..gate = Completer<void>();
    }
    // 封面预热：与页面里同一份 bytes 实例，ImageCache 才能命中。
    final covers = <Uint8List>[];
    if (!loading) {
      for (final book in demoOndeck()) {
        final bytes = await repository.bookCover(book.id);
        if (bytes != null) covers.add(bytes);
      }
      for (final series in demoShelf()) {
        final bytes = await repository.seriesCover(series.id);
        if (bytes != null) covers.add(bytes);
      }
    }
    await pumpGoldenScreen(
      tester,
      screen: const ReadingNowScreen(),
      size: size,
      theme: theme,
      overrides: <Override>[
        ...testSourceOverrides(library: repository),
        // "最近阅读"横滑条读本地会话表（HIS-02 / ARC-06 用户库）：黄金图环境没有 path_provider，
        // 必须换成内存库，否则整页停在 MissingPluginException。
        progressDatabaseProvider.overrideWithValue(
          ProgressDatabase(NativeDatabase.memory()),
        ),
      ],
      precacheImages: covers,
      // 骨架的微光是无限循环动画，settle 会把 pumpAndSettle 拖到超时。
      settle: !loading,
      realTimeSettle: !loading,
    );
    await expectGolden(tester, name);
  }

  Future<void> pumpDownloadsGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
  }) async {
    final db = HttpCacheDatabase(NativeDatabase.memory());
    await db.markDownloaded(
      scope: kTestKomgaSourceKey,
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
        ...testSourceOverrides(
          library: library,
          download: _GoldenDownloadService(),
        ),
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

  testWidgets('reading_now_loading@phone_light', (WidgetTester tester) async {
    // FIX-05：加载中必须是骨架，不能先画"还没有在读的书"。
    await pumpReadingNowGolden(
      tester,
      name: 'reading_now_loading@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      loading: true,
    );
  });

  /// Insights（HIS-03）：连续天数 + 周/月 + 12 周热力图。
  ///
  /// "今天"固定成下面这个日期，造数据与渲染都用它。
  /// 别改回 `DateTime.now()`：周/月汇总相对"今天"算，跟着系统时钟走的基线
  /// 在别的日期或时区必然失配（CI 跑 UTC、本地跑 +08，跨日就把"本月"
  /// 从 270 分钟算成 252 分钟，三张 insights 基线全红过）。
  final DateTime insightsNow = DateTime(2026, 11, 25, 20, 30);
  Future<void> pumpInsightsGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    bool empty = false,
  }) async {
    final db = ProgressDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    if (!empty) {
      final now = insightsNow;
      for (var i = 0; i < 21; i++) {
        // 隔三差五地读：热力图有明显深浅，连续天数不是一条直线。
        if (i % 4 == 0) continue;
        final startedAt = now.subtract(Duration(days: i, hours: 3));
        final minutes = (i % 3 + 1) * 12;
        await db.addReadingSession(
          bookId: 'b${i % 3}',
          seriesId: 's1',
          bookName: 'Vol. ${i % 3}',
          startedAt: startedAt,
          endedAt: startedAt.add(Duration(minutes: minutes)),
          durationMs: minutes * 60 * 1000,
          startPage: 1,
          endPage: 20,
          completed: false,
        );
      }
      // 最近一天再加一本不同书，让黄金图展示多本封面 + 书名的横向排版。
      final latestDay = now.subtract(const Duration(days: 1, hours: 1));
      await db.addReadingSession(
        bookId: 'b2',
        seriesId: 's2',
        bookName: 'Dune Vol. 2',
        startedAt: latestDay,
        endedAt: latestDay.add(const Duration(minutes: 20)),
        durationMs: 20 * 60 * 1000,
        startPage: 1,
        endPage: 24,
        completed: false,
      );
    }
    final fake = FakeLibraryRepository(series: demoShelf());
    await pumpGoldenScreen(
      tester,
      screen: InsightsScreen(now: insightsNow),
      size: size,
      theme: theme,
      overrides: <Override>[
        progressDatabaseProvider.overrideWithValue(db),
        ...testSourceOverrides(library: fake),
      ],
      realTimeSettle: true,
    );
    await expectGolden(tester, name);
  }

  testWidgets('insights@phone_light', (WidgetTester tester) async {
    await pumpInsightsGolden(
      tester,
      name: 'insights@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
    );
  });

  testWidgets('insights@tablet_dark', (WidgetTester tester) async {
    await pumpInsightsGolden(
      tester,
      name: 'insights@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
    );
  });

  testWidgets('insights@eink', (WidgetTester tester) async {
    await pumpInsightsGolden(
      tester,
      name: 'insights@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
    );
  });

  testWidgets('settings@phone_light_text2.0', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const SettingsScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      textScale: 2.0,
      overrides: <Override>[
        ...memorySession(connected: true),
        httpCacheDatabaseProvider.overrideWithValue(
          HttpCacheDatabase(NativeDatabase.memory()),
        ),
      ],
    );
    await expectGolden(tester, 'settings@phone_light_text2.0');
  });

  testWidgets('settings@phone_light', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const SettingsScreen(),
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      overrides: <Override>[
        ...memorySession(connected: true),
        httpCacheDatabaseProvider.overrideWithValue(
          HttpCacheDatabase(NativeDatabase.memory()),
        ),
      ],
    );
    await expectGolden(tester, 'settings@phone_light');
  });

  testWidgets('settings@tablet_dark', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const SettingsScreen(),
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
      overrides: <Override>[
        ...memorySession(connected: true),
        httpCacheDatabaseProvider.overrideWithValue(
          HttpCacheDatabase(NativeDatabase.memory()),
        ),
      ],
    );
    await expectGolden(tester, 'settings@tablet_dark');
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

  testWidgets('connection@tablet_dark', (WidgetTester tester) async {
    await pumpGoldenScreen(
      tester,
      screen: const ConnectionScreen(),
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
      overrides: memorySession(),
    );
    await expectGolden(tester, 'connection@tablet_dark');
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
