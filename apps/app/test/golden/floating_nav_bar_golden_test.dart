import 'package:flutter_test/flutter_test.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/widgets/floating_nav_bar.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

/// 悬浮玻璃导航条的视觉基线。
///
/// 背后铺一层高对比条纹，才能看出"玻璃"到底透了多少、糊成什么样；
/// 铺纯色背景的话，毛玻璃和一块实心色条在基线上没有区别。
void main() {
  setUpAll(loadAppFonts);

  Future<void> pumpProbe(
    WidgetTester tester, {
    required String name,
    required ThemeData theme,
    double textScale = 1.0,
    int selectedTab = 1,
  }) async {
    await pumpGoldenScreen(
      tester,
      screen: _NavBarProbe(selectedTab: selectedTab),
      size: GoldenSizes.phone,
      theme: theme,
      textScale: textScale,
    );
    await expectGolden(tester, name);
  }

  testWidgets('nav_bar@phone_light', (WidgetTester tester) async {
    await pumpProbe(
      tester,
      name: 'nav_bar@phone_light',
      theme: AppTheme.light(),
    );
  });

  testWidgets('nav_bar@phone_dark', (WidgetTester tester) async {
    await pumpProbe(tester, name: 'nav_bar@phone_dark', theme: AppTheme.dark());
  });

  testWidgets('nav_bar@eink', (WidgetTester tester) async {
    await pumpProbe(tester, name: 'nav_bar@eink', theme: AppTheme.eink());
  });

  testWidgets('nav_bar@phone_light_text1.3', (WidgetTester tester) async {
    await pumpProbe(
      tester,
      name: 'nav_bar@phone_light_text1.3',
      theme: AppTheme.light(),
      textScale: 1.3,
    );
  });

  // 选中首/尾 tab 时，内层胶囊的端头半圆紧贴外层胶囊的半圆：
  // 这一张专门盯"内外同心、间隙等宽"（选中中间那格看不到端头弧线）。
  testWidgets('nav_bar@phone_light_edge', (WidgetTester tester) async {
    await pumpProbe(
      tester,
      name: 'nav_bar@phone_light_edge',
      theme: AppTheme.light(),
      selectedTab: 0,
    );
  });
}

/// 满屏彩色条纹 + 底部导航条。
class _NavBarProbe extends StatelessWidget {
  const _NavBarProbe({this.selectedTab = 1});

  /// 选中第几个 tab；0 / 末尾能看端头半圆的间隙。
  final int selectedTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const _Stripes(),
          Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNavBar(
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
              selectedTab: selectedTab,
              onTabSelected: (_) {},
              search: const GlassNavDestination(
                icon: Icons.search,
                label: 'Search',
              ),
              onSearch: () {},
            ),
          ),
        ],
      ),
    );
  }
}

/// 高对比条纹：彩色主题用饱和色，墨水屏用灰阶梯（灰阶上才看得出退化）。
class _Stripes extends StatelessWidget {
  const _Stripes();

  static const List<Color> _color = <Color>[
    Color(0xFFE53935),
    Color(0xFFFFB300),
    Color(0xFF43A047),
    Color(0xFF1E88E5),
    Color(0xFF8E24AA),
    Color(0xFF00897B),
  ];

  static const List<Color> _gray = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFFD0D0D0),
    Color(0xFF909090),
    Color(0xFF505050),
    Color(0xFF202020),
    Color(0xFF000000),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.isEink(Theme.of(context)) ? _gray : _color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < 18; i++)
          Expanded(child: ColoredBox(color: palette[i % palette.length])),
      ],
    );
  }
}
