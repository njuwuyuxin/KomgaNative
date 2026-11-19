import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/widgets/floating_nav_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 自适应外壳：手机用底部悬浮玻璃导航，平板/桌面用侧边导航。
///
/// 断点判断只在这里做一次，页面内部不再自己判断"是不是平板"。
///
/// 手机形态下导航条是**浮层**：`extendBody` 让页面内容一直铺到屏幕底，
/// 玻璃才能真的模糊到封面/列表（否则背后只有一层纯色背景，"液态玻璃"
/// 会变成一块实心白条）。代价是页面自己要在滚动内容末尾留出
/// `AppSizes.navBarClearance`，否则最后一行会被导航条压住。
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  /// 路由分支顺序（`router.dart`）：正在读 / 书架 / 收藏 / 搜索 / 设置。
  static const int _readingBranch = 0;
  static const int _collectionsBranch = 2;
  static const int _searchBranch = 3;

  /// 胶囊里放哪几个分支：搜索单独做成右侧圆球，不占胶囊。
  ///
  /// 四个 tab + 一颗搜索球：标签必须短（"Reading" 而不是 "Reading now"），
  /// 否则 1.3 倍字号下会被截断（`nav_bar@phone_light_text1.3` 是这双眼睛）。
  static const List<int> _tabBranches = <int>[0, 1, 2, 4];

  void _onSelect(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allDestinations =
        <({IconData icon, IconData selectedIcon, String label})>[
          (
            icon: Icons.auto_stories_outlined,
            selectedIcon: Icons.auto_stories,
            label: l10n.readingNow,
          ),
          (
            icon: Icons.grid_view_outlined,
            selectedIcon: Icons.grid_view,
            label: l10n.libraryTitle,
          ),
          (
            icon: Icons.collections_bookmark_outlined,
            selectedIcon: Icons.collections_bookmark,
            label: l10n.collectionsTitle,
          ),
          (
            icon: Icons.search,
            selectedIcon: Icons.search,
            label: l10n.searchTitle,
          ),
          (
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: l10n.settingsTitle,
          ),
        ];
    final sizeClass = WindowSizeClass.of(MediaQuery.sizeOf(context).width);

    /// 胶囊里的标签：页面标题太长时用短一档的导航文案。
    String labelFor(int branch) {
      if (branch == _readingBranch) return l10n.navReadingNow;
      if (branch == _collectionsBranch) return l10n.navCollections;
      return allDestinations[branch].label;
    }

    if (!sizeClass.useNavigationRail) {
      final selectedTab = _tabBranches.indexOf(shell.currentIndex);
      return Scaffold(
        // 内容铺到屏幕底，导航条浮在它上面（见类注释）。
        extendBody: true,
        // 键盘弹出时让导航条留在原位被键盘盖住（iOS 的行为）。
        // 页面自己的 Scaffold 仍会为键盘让位，输入框不会跑出屏幕。
        resizeToAvoidBottomInset: false,
        body: shell,
        bottomNavigationBar: FloatingNavBar(
          tabs: <GlassNavDestination>[
            for (var i = 0; i < _tabBranches.length; i++)
              GlassNavDestination(
                icon: allDestinations[_tabBranches[i]].icon,
                selectedIcon: allDestinations[_tabBranches[i]].selectedIcon,
                // 收藏页面的完整标题是 "Collections"，四格胶囊里放不下，
                // 导航栏用短一档的 "Saved" / "收藏"（页面内容不变）。
                label: labelFor(_tabBranches[i]),
                key: Key('nav-tab-${_tabBranches[i]}'),
              ),
          ],
          selectedTab: selectedTab < 0 ? null : selectedTab,
          onTabSelected: (int index) => _onSelect(_tabBranches[index]),
          search: GlassNavDestination(
            icon: allDestinations[_searchBranch].icon,
            label: allDestinations[_searchBranch].label,
            key: const Key('nav-tab-search'),
          ),
          searchSelected: shell.currentIndex == _searchBranch,
          onSearch: () => _onSelect(_searchBranch),
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _onSelect,
            labelType: NavigationRailLabelType.all,
            destinations: <NavigationRailDestination>[
              for (final d in allDestinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: AppSizes.hairline),
          Expanded(child: shell),
        ],
      ),
    );
  }
}
