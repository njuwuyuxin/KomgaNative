import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/cache/drift_http_cache.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/widgets/floating_nav_bar.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

import '../support/fake_library.dart';
import '../support/test_source_overrides.dart';
import 'golden_harness.dart';

/// 书架页 UI 基线矩阵（网格、列表、多选、离线、菜单、空态、错误态）。
void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpShelfGolden(
    WidgetTester tester, {
    required String name,
    required Size size,
    required ThemeData theme,
    double textScale = 1.0,
    Locale? locale,
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

    // 离线提示由缓存实例广播：必须在首帧之前通过两次核心失败确认离线，
    // 这样既走真实滤波阈值，也不留挂起定时器且基线第一帧就画得出来。
    final cache = DriftHttpCache(
      HttpCacheDatabase(NativeDatabase.memory()),
      now: () => DateTime.utc(2026, 11, 25, 12),
    );
    addTearDown(cache.dispose);
    if (offline) {
      cache
        ..reportOffline('https://komga.example.com')
        ..reportOffline('https://komga.example.com');
    }

    await pumpGoldenScreen(
      tester,
      screen: withNavBar
          ? const _WithFloatingNavBar(child: LibraryScreen())
          : const LibraryScreen(),
      size: size,
      theme: theme,
      textScale: textScale,
      locale: locale ?? const Locale('en'),
      overrides: <Override>[
        ...testSourceOverrides(library: repository),
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

  /// 管理书籍态（LIB-03）：顶部栏原地形变为「管理书籍」胶囊 + 退出圆球 + 全标已读/未读/收藏集三格胶囊，
  /// 大标题行切换为「已选 N / 全选」，选中封面轻微内收并呈现柔光遮罩 + 右上角对勾，未选封面呈现空心环。
  Future<void> enterAndSelectShelf(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('shelf-select-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('series-s2')));
    await tester.pumpAndSettle();
  }

  testWidgets('library_selection@phone_light', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_selection@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      withNavBar: true,
      act: enterAndSelectShelf,
    );
  });

  testWidgets('library_selection@tablet_dark', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_selection@tablet_dark',
      size: GoldenSizes.tablet,
      theme: AppTheme.dark(),
      act: enterAndSelectShelf,
    );
  });

  testWidgets('library_selection@eink', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_selection@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
      act: enterAndSelectShelf,
    );
  });

  testWidgets('library_list_selection@phone_light', (
    WidgetTester tester,
  ) async {
    await pumpShelfGolden(
      tester,
      name: 'library_list_selection@phone_light',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      act: (WidgetTester tester) async {
        await tester.tap(find.byKey(const Key('shelf-view-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('List'));
        await tester.pumpAndSettle();
        await enterAndSelectShelf(tester);
      },
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

  testWidgets('library@phone_light_text2.0', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library@phone_light_text2.0',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      textScale: 2.0,
    );
  });

  testWidgets('library@phone_light_zh', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library@phone_light_zh',
      size: GoldenSizes.phone,
      theme: AppTheme.light(),
      locale: const Locale('zh'),
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
      withNavBar: true,
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

  /// 墨水屏的二级菜单：玻璃退化成纸底墨框，但仍然是圆角卡 + 居中文案。
  testWidgets('library_sort_menu@eink', (WidgetTester tester) async {
    await pumpShelfGolden(
      tester,
      name: 'library_sort_menu@eink',
      size: GoldenSizes.eink,
      theme: AppTheme.eink(),
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
            icon: Icons.collections_bookmark_outlined,
            selectedIcon: Icons.collections_bookmark,
            label: 'Saved',
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
