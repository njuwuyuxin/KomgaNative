import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/l10n/l10n.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/shelf_selection_provider.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/widgets/floating_nav_bar.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_library.dart';

/// LIB-03：书架多选与批量操作。
///
/// 入口是顶部工具条的"选择"按钮，**不是长按**：长按在书架上是系列菜单
/// （标记已读/置顶/详情），一个手势不能同时做两件事。
void main() {
  late FakeLibraryRepository repository;

  Future<ProviderContainer> pumpShelf(WidgetTester tester) async {
    repository = FakeLibraryRepository(series: demoShelf());
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
  }

  /// 点"选择"进入多选态。
  Future<void> enterSelection(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('shelf-select-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('进入多选后点卡片是勾选，不是打开系列', (WidgetTester tester) async {
    final container = await pumpShelf(tester);
    final ids = (await repository.series(
      page: 0,
      size: 20,
    )).items.map((s) => s.id).toList();

    await enterSelection(tester);
    expect(find.byKey(const Key('shelf-selection-bar')), findsOneWidget);

    await tester.tap(find.byKey(Key('series-${ids[0]}')));
    await tester.pumpAndSettle();
    expect(container.read(shelfSelectionProvider).ids, <String>{ids[0]});

    // 点第二张卡片：加选，而不是进系列页。
    await tester.tap(find.byKey(Key('series-${ids[1]}')));
    await tester.pumpAndSettle();
    expect(container.read(shelfSelectionProvider).ids.length, 2);
    expect(find.byKey(const Key('shelf-search-field')), findsNothing);
  });

  testWidgets('全选与取消', (WidgetTester tester) async {
    final container = await pumpShelf(tester);
    final total = (await repository.series(page: 0, size: 20)).items.length;

    await enterSelection(tester);
    await tester.tap(find.byKey(const Key('shelf-selection-all')));
    await tester.pumpAndSettle();
    expect(container.read(shelfSelectionProvider).ids.length, total);

    await tester.tap(find.byKey(const Key('shelf-selection-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shelf-selection-bar')), findsNothing);
    expect(container.read(shelfSelectionProvider).ids, isEmpty);
    expect(container.read(shelfSelectionProvider).active, isFalse);
  });

  testWidgets('批量标记已读：逐个调用并退出多选', (WidgetTester tester) async {
    final container = await pumpShelf(tester);

    await enterSelection(tester);
    await tester.tap(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('series-s2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shelf-batch-read')));
    await tester.pumpAndSettle();

    expect(repository.seriesReadCalls.length, 2);
    expect(repository.seriesReadCalls.every((c) => c.read), isTrue);
    expect(container.read(shelfSelectionProvider).ids, isEmpty);
    expect(find.byKey(const Key('shelf-selection-bar')), findsNothing);
    expect(find.text('Marked 2 books as read'), findsOneWidget);
  });

  testWidgets('中文环境下批量标为已读/未读弹出明确操作文案', (WidgetTester tester) async {
    repository = FakeLibraryRepository(series: demoShelf());
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await enterSelection(tester);
    await tester.tap(find.byKey(const Key('series-s1')));
    await tester.tap(find.byKey(const Key('series-s2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-batch-read')));
    await tester.pumpAndSettle();
    expect(find.text('已将 2 本书标为已读'), findsOneWidget);

    await enterSelection(tester);
    await tester.tap(find.byKey(const Key('series-s1')));
    await tester.tap(find.byKey(const Key('series-s2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-batch-unread')));
    await tester.pumpAndSettle();
    expect(find.text('已将 2 本书标为未读'), findsOneWidget);
  });

  testWidgets('失败项不影响其余项', (WidgetTester tester) async {
    final container = await pumpShelf(tester);
    await enterSelection(tester);
    await tester.tap(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('series-s2')));
    await tester.pumpAndSettle();
    // 让每一次标记都失败。
    repository.seriesReadFailure = const UnexpectedFailure('boom');

    await tester.tap(find.byKey(const Key('shelf-batch-read')));
    await tester.pumpAndSettle();

    expect(repository.seriesReadCalls.length, 2, reason: '一个失败不影响下一个');
    expect(container.read(shelfSelectionProvider).ids, isEmpty);
  });

  testWidgets('列表视图（ShelfView.list）多选模式下长按系列行触发勾选而非弹菜单', (
    WidgetTester tester,
  ) async {
    final container = await pumpShelf(tester);

    await tester.tap(find.byKey(const Key('shelf-view-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shelf-view-list')));
    await tester.pumpAndSettle();

    await enterSelection(tester);

    await tester.longPress(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();

    expect(container.read(shelfSelectionProvider).ids, <String>{'s1'});
    expect(find.text('View details'), findsNothing);

    await tester.longPress(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();
    expect(container.read(shelfSelectionProvider).ids, isEmpty);
  });

  testWidgets('进入管理模式后三个批量按钮原地形变到顶部栏，底部无重复悬浮条且视口不被压缩', (
    WidgetTester tester,
  ) async {
    repository = FakeLibraryRepository(series: demoShelf());
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: Scaffold(
            extendBody: true,
            body: const LibraryScreen(),
            bottomNavigationBar: FloatingNavBar(
              tabs: const <GlassNavDestination>[
                GlassNavDestination(
                  icon: Icons.auto_stories_outlined,
                  label: 'Reading',
                ),
                GlassNavDestination(
                  icon: Icons.grid_view_outlined,
                  label: 'Library',
                  key: Key('dock-library-tab'),
                ),
                GlassNavDestination(
                  icon: Icons.collections_bookmark_outlined,
                  label: 'Saved',
                ),
                GlassNavDestination(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                ),
              ],
              selectedTab: 1,
              onTabSelected: (_) {},
              search: const GlassNavDestination(
                icon: Icons.search,
                label: 'Search',
              ),
              onSearch: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollBefore = tester.getRect(find.byKey(const Key('shelf-scroll')));
    final sortBefore = tester.getRect(find.byKey(const Key('shelf-sort-menu')));
    final filterBefore = tester.getRect(
      find.byKey(const Key('shelf-filter-menu')),
    );
    final viewBefore = tester.getRect(find.byKey(const Key('shelf-view-menu')));
    final selectOrbBefore = tester.getRect(
      find.byKey(const Key('shelf-select-button')),
    );

    // 点击管理按钮后在形变过渡中段（120ms）新旧按钮同场交叉过渡。
    await tester.tap(find.byKey(const Key('shelf-select-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Manage books'), findsOneWidget);
    expect(find.byKey(const Key('shelf-batch-read')), findsOneWidget);
    expect(find.byKey(const Key('shelf-sort-menu')), findsOneWidget);

    await tester.pumpAndSettle();

    // 滚动视口本身不被压缩（底部无新增悬浮条）；多选紧凑信息行展开。
    expect(
      tester.getRect(find.byKey(const Key('shelf-scroll'))),
      equals(scrollBefore),
    );
    expect(find.byKey(const Key('shelf-selection-count')), findsOneWidget);
    expect(find.byKey(const Key('shelf-selection-all')), findsOneWidget);

    // 顶部左侧搜索栏变为「Manage books」，中间圆球原地形变为退出键，
    // 右侧三格原地形变为全标已读 / 全标未读 / 收藏集（与原按钮坐标一致）。
    expect(find.text('Manage books'), findsOneWidget);
    expect(find.byKey(const Key('shelf-search-field')), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('shelf-selection-close'))),
      equals(selectOrbBefore),
    );
    expect(
      tester.getRect(find.byKey(const Key('shelf-batch-read'))),
      equals(sortBefore),
    );
    expect(
      tester.getRect(find.byKey(const Key('shelf-batch-unread'))),
      equals(filterBefore),
    );
    expect(
      tester.getRect(find.byKey(const Key('shelf-batch-collection'))),
      equals(viewBefore),
    );

    // 顶部批量条位于页面顶部，与底部 dock 保持远距（底部无悬浮条）。
    final batchRect = tester.getRect(find.byKey(const Key('shelf-batch-bar')));
    final dockTabRect = tester.getRect(
      find.byKey(const Key('dock-library-tab')),
    );
    expect(batchRect.top, lessThan(AppSizes.glassHeaderClearance));
    expect(dockTabRect.top - batchRect.bottom, greaterThan(400));

    // 未选任何系列（按钮禁用）时点击批量按钮不会触发批量标记。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LibraryScreen)),
    );
    await tester.tap(
      find.byKey(const Key('shelf-batch-read')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(container.read(shelfSelectionProvider).ids, isEmpty);
    expect(repository.seriesReadCalls, isEmpty);
  });

  testWidgets('墨水屏下进出管理模式直接瞬切，不播形变动画', (WidgetTester tester) async {
    repository = FakeLibraryRepository(series: demoShelf());
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          libraryRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.eink(),
          home: const LibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shelf-select-button')));
    await tester.pump();

    expect(find.text('管理书籍'), findsOneWidget);
    expect(find.byKey(const Key('shelf-selection-bar')), findsOneWidget);
    expect(find.byKey(const Key('shelf-search-field')), findsNothing);
    expect(find.byKey(const Key('shelf-sort-menu')), findsNothing);
    expect(find.byKey(const Key('shelf-batch-read')), findsOneWidget);
  });

  testWidgets('多选卡片用封面内角标与柔和视觉表达选中，不再套外框线', (WidgetTester tester) async {
    await pumpShelf(tester);

    // 常态浏览无选择徽章。
    expect(find.byType(SelectionBadge), findsNothing);

    await enterSelection(tester);

    // 进入管理模式后，每张可见卡片都出现空心选择环，但尚未出现对勾。
    expect(find.byType(SelectionBadge), findsWidgets);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.tap(find.byKey(const Key('series-s1')));
    await tester.pumpAndSettle();

    // 仅选中的卡片出现对勾，且整个卡片外部没有 hairline 线框 DecoratedBox。
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    final selectedTile = find.byKey(const Key('series-s1'));
    final ancestorWireframes = tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: selectedTile, matching: find.byType(DecoratedBox)),
        )
        .where(
          (DecoratedBox box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).border != null,
        );
    expect(ancestorWireframes, isEmpty);
  });
}
