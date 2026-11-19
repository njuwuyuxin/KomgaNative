import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/widgets/floating_nav_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 悬浮玻璃导航条：点击派发、点按区、语义、墨水屏退化。
void main() {
  const tabs = <GlassNavDestination>[
    GlassNavDestination(
      icon: Icons.auto_stories_outlined,
      selectedIcon: Icons.auto_stories,
      label: 'Reading',
      key: Key('nav-tab-0'),
    ),
    GlassNavDestination(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view,
      label: 'Library',
      key: Key('nav-tab-1'),
    ),
    GlassNavDestination(
      icon: Icons.collections_bookmark_outlined,
      selectedIcon: Icons.collections_bookmark,
      label: 'Saved',
      key: Key('nav-tab-2'),
    ),
    GlassNavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      key: Key('nav-tab-3'),
    ),
  ];
  const search = GlassNavDestination(
    icon: Icons.search,
    label: 'Search',
    key: Key('nav-tab-search'),
  );

  Future<void> pumpBar(
    WidgetTester tester, {
    ThemeData? theme,
    int? selectedTab = 0,
    bool searchSelected = false,
    ValueChanged<int>? onTabSelected,
    VoidCallback? onSearch,
    double textScale = 1.0,
    ValueNotifier<int?>? selection,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child ?? const SizedBox.shrink(),
        ),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: selection == null
              ? FloatingNavBar(
                  tabs: tabs,
                  selectedTab: selectedTab,
                  onTabSelected: onTabSelected ?? (_) {},
                  search: search,
                  searchSelected: searchSelected,
                  onSearch: onSearch ?? () {},
                )
              : ValueListenableBuilder<int?>(
                  valueListenable: selection,
                  builder: (BuildContext context, int? value, _) =>
                      FloatingNavBar(
                        tabs: tabs,
                        selectedTab: value,
                        onTabSelected: onTabSelected ?? (_) {},
                        search: search,
                        searchSelected: searchSelected,
                        onSearch: onSearch ?? () {},
                      ),
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('四个 tab 都是 48 点按区，点击派发下标', (WidgetTester tester) async {
    final taps = <int>[];
    await pumpBar(tester, onTabSelected: taps.add);

    for (var i = 0; i < tabs.length; i++) {
      final finder = find.byKey(Key('nav-tab-$i'));
      final size = tester.getSize(finder);
      expect(size.height, greaterThanOrEqualTo(AppSizes.minTouch));
      expect(size.width, greaterThanOrEqualTo(AppSizes.minTouch));

      await tester.tap(finder);
      await tester.pumpAndSettle();
    }
    expect(taps, <int>[0, 1, 2, 3]);
  });

  testWidgets('选中项有 selected 语义，其余是普通按钮', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester, selectedTab: 1);

    final selected = tester.getSemantics(find.byKey(const Key('nav-tab-1')));
    expect(selected.label, 'Library');
    expect(selected.flagsCollection.isButton, isTrue);
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);

    final unselected = tester.getSemantics(find.byKey(const Key('nav-tab-0')));
    expect(unselected.label, 'Reading');
    expect(unselected.flagsCollection.isButton, isTrue);
    expect(unselected.flagsCollection.isSelected, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('搜索圆球：语义标签来自文案，点击走 onSearch', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    var searches = 0;
    await pumpBar(tester, onSearch: () => searches++);

    final finder = find.byKey(const Key('nav-tab-search'));
    final node = tester.getSemantics(finder);
    expect(node.label, 'Search');
    expect(node.flagsCollection.isButton, isTrue);
    expect(
      tester.getSize(finder).width,
      greaterThanOrEqualTo(AppSizes.minTouch),
    );

    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(searches, 1);
    handle.dispose();
  });

  testWidgets('墨水屏：不模糊、选中项反白（墨底纸白图标）', (WidgetTester tester) async {
    await pumpBar(tester, theme: AppTheme.eink(), selectedTab: 0);

    expect(find.byType(BackdropFilter), findsNothing);
    final selectedIcon = tester.widget<Icon>(find.byIcon(Icons.auto_stories));
    expect(selectedIcon.color, AppTheme.einkPaper);
    final otherIcon = tester.widget<Icon>(
      find.byIcon(Icons.grid_view_outlined),
    );
    expect(otherIcon.color, AppTheme.einkInk);
  });

  testWidgets('文本放大 1.3 倍不溢出', (WidgetTester tester) async {
    await pumpBar(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Reading'), findsOneWidget);
  });

  testWidgets('选中胶囊四边等宽内缩，端头半圆与外层同心', (WidgetTester tester) async {
    await pumpBar(tester, selectedTab: 0);

    final pill = tester.getRect(find.byType(GlassSurface).first);
    final indicator = tester.getRect(
      find.byKey(const Key('sliding-selection-pill')),
    );
    final selectedItem = tester.getRect(find.byKey(const Key('nav-tab-0')));

    // 四个方向的内缩必须一样：横向多 4 时，端头的半圆会和外层错开。
    expect(
      indicator.left - selectedItem.left,
      moreOrLessEquals(navIndicatorInset, epsilon: 0.01),
    );
    expect(
      selectedItem.right - indicator.right,
      moreOrLessEquals(navIndicatorInset, epsilon: 0.01),
    );
    expect(
      indicator.top - selectedItem.top,
      moreOrLessEquals(navIndicatorInset, epsilon: 0.01),
    );
    expect(
      selectedItem.bottom - indicator.bottom,
      moreOrLessEquals(navIndicatorInset, epsilon: 0.01),
    );

    // 外层是胶囊（半径 = 高/2），内层也是胶囊：半径差恰好等于间隙，
    // 这才是"同心圆"；只有高度差对了还不够。
    final outerRadius = pill.height / 2;
    final innerRadius = indicator.height / 2;
    expect(
      outerRadius - innerRadius,
      moreOrLessEquals(navIndicatorInset, epsilon: 0.01),
    );

    // 四个槽位等宽，首尾槽位贴住外层胶囊：中间不能再夹一层横向 padding，
    // 否则端头 tab 的左右内缩会比上下大。
    final items = <Rect>[
      for (var i = 0; i < tabs.length; i++)
        tester.getRect(find.byKey(Key('nav-tab-$i'))),
    ];
    for (final item in items) {
      expect(
        item.width,
        moreOrLessEquals(items.first.width, epsilon: 0.01),
        reason: '等分槽位，胶囊滑动距离才可预测',
      );
    }
    expect(items.first.left, moreOrLessEquals(pill.left, epsilon: 0.01));
    expect(items.last.right, moreOrLessEquals(pill.right, epsilon: 0.01));
  });

  testWidgets('切换 tab 时选中胶囊从旧格弹簧滑到新格', (WidgetTester tester) async {
    final selection = ValueNotifier<int?>(0);
    addTearDown(selection.dispose);
    await pumpBar(
      tester,
      selection: selection,
      onTabSelected: (int index) => selection.value = index,
    );

    final from = tester.getRect(
      find.byKey(const Key('sliding-selection-pill')),
    );
    final targetItem = tester.getRect(find.byKey(const Key('nav-tab-3')));
    final targetLeft = targetItem.left + navIndicatorInset;

    await tester.tap(find.byKey(const Key('nav-tab-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final midway = tester.getRect(
      find.byKey(const Key('sliding-selection-pill')),
    );
    expect(midway.left, greaterThan(from.left + 1));
    expect(
      midway.left,
      lessThan(targetLeft - 1),
      reason: '60ms 时应还在半路，而不是瞬间到位',
    );

    await tester.pumpAndSettle();
    final settled = tester.getRect(
      find.byKey(const Key('sliding-selection-pill')),
    );
    expect(settled.left, moreOrLessEquals(targetLeft, epsilon: 0.01));
    expect(
      settled.width,
      moreOrLessEquals(targetItem.width - navIndicatorInset * 2, epsilon: 0.01),
    );
  });

  testWidgets('墨水屏：切换 tab 不跑弹簧，直接到新格', (WidgetTester tester) async {
    final selection = ValueNotifier<int?>(0);
    addTearDown(selection.dispose);
    await pumpBar(
      tester,
      theme: AppTheme.eink(),
      selection: selection,
      onTabSelected: (int index) => selection.value = index,
    );

    await tester.tap(find.byKey(const Key('nav-tab-2')));
    await tester.pump();

    final targetItem = tester.getRect(find.byKey(const Key('nav-tab-2')));
    final indicator = tester.getRect(
      find.byKey(const Key('sliding-selection-pill')),
    );
    expect(
      indicator.left,
      moreOrLessEquals(targetItem.left + navIndicatorInset, epsilon: 0.01),
    );
  });
}
