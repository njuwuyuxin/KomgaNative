import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/search_providers.dart';
import 'package:yomu/src/widgets/floating_nav_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 自适应外壳：手机用底部悬浮玻璃导航，平板/桌面用侧边导航。
///
/// 断点判断只在这里做一次，页面内部不再自己判断"是不是平板"。
///
/// 手机形态下导航条是**浮层**：`extendBody` 让页面内容一直铺到屏幕底，
/// 玻璃才能真的模糊到封面/列表（否则背后只有一层纯色背景，"液态玻璃"
/// 会变成一块实心白条）。代价是页面自己要在滚动内容末尾留出
/// `AppSizes.navBarClearance`，否则最后一行会被导航条压住。
class AdaptiveShell extends ConsumerStatefulWidget {
  const AdaptiveShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  /// 路由分支顺序（`router.dart`）：正在读 / 书架 / 收藏 / 设置 / 搜索。
  /// 搜索放在最右侧，与底部悬浮导航条的搜索圆球位置及进出滑动方向一致。
  static const int _readingBranch = 0;
  static const int _collectionsBranch = 2;
  static const int _searchBranch = 4;

  /// 胶囊里放哪几个分支：搜索单独做成右侧圆球，不占胶囊。
  ///
  /// 四个 tab + 一颗搜索球：标签必须短（"Reading" 而不是 "Reading now"），
  /// 否则 1.3 倍字号下会被截断（`nav_bar@phone_light_text1.3` 是这双眼睛）。
  static const List<int> _tabBranches = <int>[0, 1, 2, 3];

  @override
  ConsumerState<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends ConsumerState<AdaptiveShell> {
  /// 上一次观察到的分支下标：用于检测进入搜索页的边沿变化。
  late int _lastBranch;

  /// 进入搜索页前所在的非搜索分支：在搜索页手势返回时回到进入前的页面，
  /// 而不是把根壳直接 pop 掉退出应用。
  int? _returnBranch;

  @override
  void initState() {
    super.initState();
    _lastBranch = widget.shell.currentIndex;
    if (_lastBranch != AdaptiveShell._searchBranch) {
      _returnBranch = _lastBranch;
    }
  }

  @override
  void didUpdateWidget(covariant AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.shell.currentIndex;
    final previous = _lastBranch;
    _lastBranch = current;
    if (current != AdaptiveShell._searchBranch) {
      _returnBranch = current;
    } else if (previous != AdaptiveShell._searchBranch) {
      // 从其他分支再次切入常驻搜索页时，等本帧移出 Offstage 后再请求聚焦弹出键盘。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            widget.shell.currentIndex != AdaptiveShell._searchBranch) {
          return;
        }
        ref.read(searchFocusRequestProvider.notifier).request();
      });
    }
  }

  void _onSelect(int index) {
    final current = widget.shell.currentIndex;
    if (index == AdaptiveShell._searchBranch &&
        current != AdaptiveShell._searchBranch) {
      _returnBranch = current;
    } else if (index == AdaptiveShell._searchBranch &&
        current == AdaptiveShell._searchBranch) {
      // 已停留在搜索页但键盘被点空白收起时，再次点搜索圆球重新弹出键盘。
      ref.read(searchFocusRequestProvider.notifier).request();
    } else if (current == AdaptiveShell._searchBranch &&
        index != AdaptiveShell._searchBranch) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    widget.shell.goBranch(index, initialLocation: index == current);
  }

  void _handlePop(bool didPop, Object? _) {
    if (didPop) return;
    final target = _returnBranch;
    if (widget.shell.currentIndex == AdaptiveShell._searchBranch &&
        target != null) {
      FocusManager.instance.primaryFocus?.unfocus();
      widget.shell.goBranch(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
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
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: l10n.settingsTitle,
          ),
          (
            icon: Icons.search,
            selectedIcon: Icons.search,
            label: l10n.searchTitle,
          ),
        ];
    final sizeClass = WindowSizeClass.of(MediaQuery.sizeOf(context).width);

    /// 胶囊里的标签：页面标题太长时用短一档的导航文案。
    String labelFor(int branch) {
      if (branch == AdaptiveShell._readingBranch) return l10n.navReadingNow;
      if (branch == AdaptiveShell._collectionsBranch) {
        return l10n.navCollections;
      }
      return allDestinations[branch].label;
    }

    final Widget scaffold;
    if (!sizeClass.useNavigationRail) {
      final selectedTab = AdaptiveShell._tabBranches.indexOf(
        shell.currentIndex,
      );
      scaffold = Scaffold(
        // 内容铺到屏幕底，导航条浮在它上面（见类注释）。
        extendBody: true,
        // 键盘弹出时让导航条留在原位被键盘盖住（iOS 的行为）。
        // 页面自己的 Scaffold 仍会为键盘让位，输入框不会跑出屏幕。
        resizeToAvoidBottomInset: false,
        body: shell,
        bottomNavigationBar: FloatingNavBar(
          tabs: <GlassNavDestination>[
            for (var i = 0; i < AdaptiveShell._tabBranches.length; i++)
              GlassNavDestination(
                icon: allDestinations[AdaptiveShell._tabBranches[i]].icon,
                selectedIcon:
                    allDestinations[AdaptiveShell._tabBranches[i]].selectedIcon,
                // 收藏页面的完整标题是 "Collections"，四格胶囊里放不下，
                // 导航栏用短一档的 "Saved" / "收藏"（页面内容不变）。
                label: labelFor(AdaptiveShell._tabBranches[i]),
                key: Key('nav-tab-${AdaptiveShell._tabBranches[i]}'),
              ),
          ],
          selectedTab: selectedTab < 0 ? null : selectedTab,
          onTabSelected: (int index) =>
              _onSelect(AdaptiveShell._tabBranches[index]),
          search: GlassNavDestination(
            icon: allDestinations[AdaptiveShell._searchBranch].icon,
            label: allDestinations[AdaptiveShell._searchBranch].label,
            key: const Key('nav-tab-search'),
          ),
          searchSelected: shell.currentIndex == AdaptiveShell._searchBranch,
          onSearch: () => _onSelect(AdaptiveShell._searchBranch),
        ),
      );
    } else {
      scaffold = Scaffold(
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

    final interceptBack =
        shell.currentIndex == AdaptiveShell._searchBranch &&
        _returnBranch != null;
    return PopScope(
      canPop: !interceptBack,
      onPopInvokedWithResult: _handlePop,
      child: scaffold,
    );
  }
}
