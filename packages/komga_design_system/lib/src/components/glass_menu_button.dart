import 'package:komga_design_system/src/components/glass_icon_button.dart';
import 'package:komga_design_system/src/components/glass_surface.dart';
import 'package:komga_design_system/src/materials.dart';
import 'package:komga_design_system/src/shapes.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 玻璃图标 + 弹出菜单（排序 / 筛选 / 视图 / 更多）。
///
/// 用 `MenuAnchor` 而不是 `PopupMenuButton`：后者的水波纹与直角卡片是安卓味，
/// 而且没法把触发器做成玻璃；这里触发器复用标题栏里的 [GlassBarAction]
/// 或独立的 [GlassIconButton]。
///
/// 菜单面板自己也是液态玻璃（[GlassSurface]）：`MenuAnchor` 的 Material 底
/// 设成全透明，真正画出来的是里面那块玻璃卡——二级菜单也要和一级控件同材质。
///
/// **`clipBehavior: Clip.none` 不能省**：`MenuAnchor` 默认 `Clip.hardEdge`，
/// 会按 `MenuStyle.shape`（这里是零圆角的矩形）裁掉玻璃卡自己的阴影，
/// 圆角外就露出一块方形的硬边阴影（真机上很明显）。玻璃卡内部已经由
/// [FrostedSurface] 自己按形状裁剪，这里再包一层透明 Material 承接水波纹，
/// 让点击反馈仍然裁在圆角内。
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

  /// 菜单项：由调用方构造 [GlassMenuItemButton] / `MenuDivider`，key 挂在项上。
  final List<Widget> menuChildren;

  /// true = 独立玻璃圆球；false = 玻璃条内部的图标（标题栏动作）。
  final bool orb;

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpacing.xs),
      // 不裁面板：见类注释。玻璃卡自己会裁内容，阴影必须能画到面板矩形外。
      clipBehavior: Clip.none,
      // 面板本体透明：可见的玻璃底由下面 menuChildren 里的 GlassSurface 画。
      // 不用 Material 的 elevation 阴影（测试渲染器上高 elevation 会画成一圈
      // 生硬黑边），浮起感交给 GlassSurface 的 AppShadows.floating。
      style: const MenuStyle(
        backgroundColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        elevation: WidgetStatePropertyAll<double>(0),
        shadowColor: WidgetStatePropertyAll<Color>(Colors.transparent),
        side: WidgetStatePropertyAll<BorderSide>(BorderSide.none),
        shape: WidgetStatePropertyAll<OutlinedBorder>(RoundedRectangleBorder()),
        padding: WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
      ),
      menuChildren: <Widget>[
        GlassSurface(
          shape: AppShapes.of(context, AppShapes.panel),
          shadows: AppShadows.floating,
          child: Material(
            // 透明的内层 Material 只负责接住 MenuItemButton 的水波纹：
            // 它在外层 Clip.none 之后、玻璃卡裁剪之内，反馈不会溢出圆角。
            type: MaterialType.transparency,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: menuChildren,
              ),
            ),
          ),
        ),
      ],
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

/// 玻璃菜单里的一行：**文本始终居中**，选中对勾放在左侧独立槽位。
///
/// 为什么不用 `MenuItemButton(leadingIcon: check)`：leadingIcon 会把文本往右挤，
/// 不同项（有没有对勾）之间的文字会左右跳。这里把对勾放进等宽的左槽位，
/// 右边再放一个同宽空槽位，文本的中心始终等于菜单的中心线。
class GlassMenuItemButton extends StatelessWidget {
  const GlassMenuItemButton({
    required this.label,
    required this.onPressed,
    this.checked = false,
    this.icon,
    this.enabled = true,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final bool checked;

  /// 未选中时可选的左侧图标（排序/筛选菜单目前不用，留给后续）。
  final IconData? icon;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MenuItemButton(
      onPressed: enabled ? onPressed : null,
      // 对勾用 Positioned 叠在左侧，**不参与** Row 的宽度分配：
      // 文本始终按整条菜单的中线居中，不管这一项有没有对勾。
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.iconLg),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          if (checked)
            const Positioned(
              left: AppSpacing.xs,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(Icons.check, size: AppSizes.iconXs),
              ),
            )
          else if (icon != null)
            Positioned(
              left: AppSpacing.xs,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(icon, size: AppSizes.iconXs),
              ),
            ),
        ],
      ),
    );
  }
}
