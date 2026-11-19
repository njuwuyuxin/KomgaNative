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
      label: 'Reading now',
      key: Key('nav-tab-0'),
    ),
    GlassNavDestination(
      icon: Icons.grid_view_outlined,
      selectedIcon: Icons.grid_view,
      label: 'Library',
      key: Key('nav-tab-1'),
    ),
    GlassNavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: 'Settings',
      key: Key('nav-tab-2'),
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
          bottomNavigationBar: FloatingNavBar(
            tabs: tabs,
            selectedTab: selectedTab,
            onTabSelected: onTabSelected ?? (_) {},
            search: search,
            searchSelected: searchSelected,
            onSearch: onSearch ?? () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('三个 tab 都是 48 点按区，点击派发下标', (WidgetTester tester) async {
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
    expect(taps, <int>[0, 1, 2]);
  });

  testWidgets('选中项有 selected 语义，其余是普通按钮', (WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await pumpBar(tester, selectedTab: 1);

    final selected = tester.getSemantics(find.byKey(const Key('nav-tab-1')));
    expect(selected.label, 'Library');
    expect(selected.flagsCollection.isButton, isTrue);
    expect(selected.flagsCollection.isSelected, Tristate.isTrue);

    final unselected = tester.getSemantics(find.byKey(const Key('nav-tab-0')));
    expect(unselected.label, 'Reading now');
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
    expect(find.text('Reading now'), findsOneWidget);
  });
}
