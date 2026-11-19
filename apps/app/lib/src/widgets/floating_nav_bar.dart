import 'dart:async';

import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 一个底部导航目标。
///
/// 图标分未选中 / 选中两版（iOS 的做法：选中变实心）。搜索圆球只有一个图标，
/// 靠 [GlassNavDestination.label] 给读屏与长按提示。
@immutable
class GlassNavDestination {
  const GlassNavDestination({
    required this.icon,
    required this.label,
    IconData? selectedIcon,
    this.key,
  }) : selectedIcon = selectedIcon ?? icon;

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// 测试 / 埋点用的稳定键。
  final Key? key;
}

/// 底部悬浮玻璃导航条：左边一条胶囊放主要的 tab，右边一颗同高的搜索圆球。
///
/// 为什么不用 Material 的 `NavigationBar`：它的高度、指示器、水波纹和
/// "整条贴底"的形态都是安卓味；这里的观感参照 iOS 26 的液态玻璃——
/// 离屏幕边缘留白、胶囊形、内容从下面模糊穿过、按下有轻微缩放。
///
/// 它只负责画和派发回调，不认路由；`AdaptiveShell` 把分支下标映射进来。
/// 墨水屏：方角、纸底墨边、选中项反白、零动画（都由 token 退化，这里不判断）。
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    required this.tabs,
    required this.selectedTab,
    required this.onTabSelected,
    required this.search,
    required this.onSearch,
    this.searchSelected = false,
    super.key,
  });

  /// 胶囊里的目标（"正在读 / 书架 / 设置"）。
  final List<GlassNavDestination> tabs;

  /// 选中的 tab 下标；在搜索页时为 null（这时胶囊里没有选中项）。
  final int? selectedTab;

  final ValueChanged<int> onTabSelected;

  /// 右侧的搜索圆球。
  final GlassNavDestination search;

  /// 搜索圆球是否处于选中态（打开搜索页时）。
  final bool searchSelected;

  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _GlassPill(
                tabs: tabs,
                selectedTab: selectedTab,
                onSelected: onTabSelected,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _SearchOrb(
              destination: search,
              selected: searchSelected,
              onTap: onSearch,
            ),
          ],
        ),
      ),
    );
  }
}

/// 装 tab 的胶囊。
class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.tabs,
    required this.selectedTab,
    required this.onSelected,
  });

  final List<GlassNavDestination> tabs;
  final int? selectedTab;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedColors = _navColors(Theme.of(context), true);
    return GlassSurface(
      shape: AppShapes.of(context, AppShapes.bar),
      child: SizedBox(
        height: AppSizes.navBarHeight,
        // 这里**不要**再加横向 padding：外层胶囊的半径是 高度/2，
        // 内层选中胶囊的 `pillInset` 四周等宽，两层才同心。
        // 选中胶囊由 [SlidingSelectionTrack] 统一绘制：切换 tab 时从旧格
        // 弹到新格（弹簧），不再是一格瞬间变深、另一格瞬间变浅。
        child: SlidingSelectionTrack(
          itemCount: tabs.length,
          selectedIndex: selectedTab,
          pillColor: selectedColors.background ?? Colors.transparent,
          pillShape: const StadiumBorder(),
          pillInset: const EdgeInsets.all(navIndicatorInset),
          // tab 之间没有空隙：旧版就是等分槽位 + 四边 4 的内缩；
          // 加 gap 会让每个槽位变窄、图标文字整体左移（黄金图能看出来）。
          gap: 0,
          itemBuilder: (BuildContext context, int index, double selection) =>
              _NavItem(
                destination: tabs[index],
                selected: selectedTab == index,
                selection: selection,
                onTap: () => onSelected(index),
              ),
        ),
      ),
    );
  }
}

/// 选中胶囊相对外层玻璃胶囊的内缩（四个方向一样宽）。
///
/// 外层是胶囊（半径 = `navBarHeight / 2`），内层也是胶囊；四周都缩这么多，
/// 内层半径正好等于 `外层半径 - navIndicatorInset`，两段半圆就同心，
/// 上下直线段与两端弧线的间隙才会一样宽。`floating_nav_bar_test` 钉了这个等式。
const double navIndicatorInset = AppSpacing.xs;

/// 胶囊里的单个 tab：图标在上、标签在下，选中时由滑动的胶囊衬底。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.selection,
    required this.onTap,
  });

  final GlassNavDestination destination;
  final bool selected;

  /// 选中进度（0 → 1）：颜色跟着滑动胶囊一起过渡。
  final double selection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColors = _navColors(theme, true);
    final unselectedColors = _navColors(theme, false);
    final unselectedForeground = unselectedColors.foreground;
    final selectedForeground = selectedColors.foreground;
    // 端点直接返回原色：Color.lerp 会经过浮点色彩空间，稳态下像素会有
    // 肉眼看不见、但黄金图能抓到的差异。
    final Color foreground = selection <= 0
        ? unselectedForeground
        : selection >= 1
        ? selectedForeground
        : Color.lerp(unselectedForeground, selectedForeground, selection) ??
              selectedForeground;

    void handleTap() {
      unawaited(AppHaptics.selection());
      onTap();
    }

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: destination.label,
      onTap: handleTap,
      // 标签本身已经念过一次，别再让读屏把图标/文字念两遍。
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            key: destination.key,
            behavior: HitTestBehavior.opaque,
            onTap: handleTap,
            // 选中胶囊铺满整个 item 槽位（iOS 26 是"整格高亮"，而不是只包住文字）。
            // 四边同宽是关键：横向多留一点，端头的半圆和外层不同心（曾经就是 8/4）。
            child: Padding(
              padding: const EdgeInsets.all(navIndicatorInset),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: AppSizes.iconLg,
                      color: foreground,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      destination.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.of(context).label
                          .copyWith(color: foreground),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 右侧的搜索圆球：不带文字，靠图标和读屏标签表达。
class _SearchOrb extends StatelessWidget {
  const _SearchOrb({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final GlassNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _navColors(theme, selected);

    void handleTap() {
      unawaited(AppHaptics.selection());
      onTap();
    }

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: destination.label,
      onTap: handleTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: destination.label,
          child: PressableScale(
            child: GestureDetector(
              key: destination.key,
              behavior: HitTestBehavior.opaque,
              onTap: handleTap,
              child: GlassSurface(
                shape: const StadiumBorder(),
                child: SizedBox(
                  width: AppSizes.navBarHeight,
                  height: AppSizes.navBarHeight,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: colors.background ?? Colors.transparent,
                    ),
                    child: Center(
                      child: Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        size: AppSizes.iconLg,
                        color: colors.foreground,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 选中 / 未选中 / 墨水屏三种情况的前景色与胶囊底色。
///
/// 彩色主题按 iOS 26：选中项是玻璃里再嵌一块**中性**的亮/暗胶囊
/// （浅色压一层白、深色提一层白），只有图标与文字用主色——
/// 整块铺主色会把玻璃"染成塑料"。
/// 墨水屏不用彩色：选中项反过来（墨底纸白图标），灰阶上一眼能认出来。
({Color foreground, Color? background}) _navColors(
  ThemeData theme,
  bool selected,
) {
  final scheme = theme.colorScheme;
  final eink = AppTheme.isEink(theme);
  if (!selected) {
    return (
      foreground: eink ? AppTheme.einkInk : scheme.onSurface,
      background: null,
    );
  }
  if (eink) {
    return (foreground: AppTheme.einkPaper, background: AppTheme.einkInk);
  }
  final optics = AppMaterial.resolve(
    AppMaterialKind.bar,
    eink: false,
    dark: theme.brightness == Brightness.dark,
  ).optics;
  return (foreground: scheme.primary, background: optics?.selectionFill);
}
