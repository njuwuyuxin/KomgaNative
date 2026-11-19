import 'package:komga_design_system/src/components/glass_icon_button.dart';
import 'package:komga_design_system/src/shapes.dart';
import 'package:komga_design_system/src/themes.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 玻璃图标 + 弹出菜单（排序 / 筛选 / 视图 / 更多）。
///
/// 用 `MenuAnchor` 而不是 `PopupMenuButton`：后者的水波纹与直角卡片是安卓味，
/// 而且没法把触发器做成玻璃；这里触发器复用标题栏里的 [GlassBarAction]
/// 或独立的 [GlassIconButton]，菜单本身是圆角浮层（墨水屏为纸底墨框）。
class GlassMenuButton extends StatelessWidget {
  const GlassMenuButton({
    required this.icon,
    required this.label,
    required this.menuChildren,
    this.orb = false,
    this.selected = false,
    super.key,
  });

  final IconData icon;

  /// 读屏标签 / 长按提示。
  final String label;

  /// 菜单项：由调用方构造 `MenuItemButton` / `MenuDivider`，key 也挂在项上。
  final List<Widget> menuChildren;

  /// true = 独立玻璃圆球；false = 玻璃条内部的图标（标题栏动作）。
  final bool orb;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final eink = AppTheme.isEink(theme);
    final base = AppShapes.of(context, AppShapes.panel);
    final outlined = base is OutlinedBorder
        ? base
        : const RoundedRectangleBorder();
    final menuShape = outlined.copyWith(
      side: eink ? const BorderSide(color: AppTheme.einkInk) : BorderSide.none,
    );

    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpacing.xs),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          eink ? AppTheme.einkPaper : scheme.surfaceContainerHigh,
        ),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Colors.transparent,
        ),
        // 不用 Material 的 elevation 阴影：测试渲染器上高 elevation 会画成
        // 一圈生硬的黑边（黄金图里量到 8px 实心黑），而 iOS 菜单是极轻的浮起。
        // 平面圆角卡 + 描边（墨水屏）已经能和背后的内容分开。
        elevation: const WidgetStatePropertyAll<double>(0),
        shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        side: WidgetStatePropertyAll<BorderSide>(
          eink ? const BorderSide(color: AppTheme.einkInk) : BorderSide.none,
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(menuShape),
        padding: const WidgetStatePropertyAll<EdgeInsets>(
          EdgeInsets.symmetric(vertical: AppSpacing.xs),
        ),
      ),
      menuChildren: menuChildren,
      builder:
          (BuildContext context, MenuController controller, Widget? child) {
            void toggle() {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            }

            if (orb) {
              return GlassIconButton(
                icon: icon,
                label: label,
                selected: selected,
                onPressed: toggle,
              );
            }
            return GlassBarAction(
              icon: icon,
              label: label,
              selected: selected,
              onPressed: toggle,
            );
          },
    );
  }
}
