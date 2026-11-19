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
    return GlassSurface(
      shape: AppShapes.of(context, AppShapes.bar),
      child: SizedBox(
        height: AppSizes.navBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            // 拉满 64 高：整块 item 都是点击区，而不是只有图标那一小块。
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < tabs.length; index++)
                _NavItem(
                  destination: tabs[index],
                  selected: selectedTab == index,
                  onTap: () => onSelected(index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 胶囊里的单个 tab：图标在上、标签在下，选中时套一层胶囊底色。
class _NavItem extends StatelessWidget {
  const _NavItem({
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
    final motion = AppMotion.of(context);
    final colors = _navColors(theme, selected);

    void handleTap() {
      unawaited(AppHaptics.selection());
      onTap();
    }

    return Expanded(
      child: Semantics(
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
              child: Padding(
                // 选中胶囊铺满整个 item 槽位（iOS 26 是"整格高亮"，而不是只包住文字），
                // 槽位之间留 4px，胶囊端头不会贴住相邻项。
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xs,
                ),
                child: AnimatedContainer(
                  // 墨水屏 / 减少动态效果时时长为 0（token 负责退化）。
                  duration: motion.quick,
                  curve: motion.standardCurve,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: colors.background ?? Colors.transparent,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        size: AppSizes.iconLg,
                        color: colors.foreground,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        destination.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.of(context).label
                            .copyWith(color: colors.foreground),
                      ),
                    ],
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
