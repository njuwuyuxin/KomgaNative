import 'dart:async';

import 'package:komga_design_system/src/components/glass_control_colors.dart';
import 'package:komga_design_system/src/components/glass_surface.dart';
import 'package:komga_design_system/src/components/pressable_scale.dart';
import 'package:komga_design_system/src/haptics.dart';
import 'package:komga_design_system/src/motion.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 一颗独立的玻璃圆球按钮（返回 / 搜索 / 更多）。
///
/// 与底部导航条的搜索圆球同一形态：圆形、浮在内容之上、按下轻微缩放、
/// 只有图标没有文字，读屏与长按提示都走 [label]。
/// 墨水屏退化成纸底墨边的方块（token 负责），这里不判断主题。
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.size = AppSizes.glassOrb,
    this.iconSize = AppSizes.iconLg,
    super.key,
  });

  final IconData icon;

  /// 读屏标签 + 长按提示（两者用同一句话，避免读两遍）。
  final String label;

  /// null = 不可点（仍然画出来，占位不跳版）。
  final VoidCallback? onPressed;

  final bool selected;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = GlassControlColors.resolve(context, selected: selected);

    void handleTap() {
      final onPressed = this.onPressed;
      if (onPressed == null) return;
      unawaited(AppHaptics.selection());
      onPressed();
    }

    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: label,
      onTap: onPressed == null ? null : handleTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: PressableScale(
            enabled: onPressed != null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPressed == null ? null : handleTap,
              child: GlassSurface(
                shape: const StadiumBorder(),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: const StadiumBorder(),
                      color: colors.fill ?? Colors.transparent,
                    ),
                    child: Center(
                      child: Icon(
                        icon,
                        size: iconSize,
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

/// 玻璃条**内部**的图标按钮（标题栏动作 / 溢出菜单）。
///
/// 不带自己的玻璃底：外层已经是 [GlassSurface]，再套一层会变成两块玻璃叠着
/// （又糊又费一次背景读取）。选中时只嵌一块中性胶囊，与导航条的 tab 一致。
///
/// 触控区 40×40：标题栏条高 56，四周留 8 就正好塞下；比 48 小一档，
/// 但整条玻璃胶囊仍是可点的，不会出现"手指够不到"的空隙。
class GlassBarAction extends StatelessWidget {
  const GlassBarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.subdued = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  /// 默认比主前景低一档：标题栏里一排图标不该比标题更抢眼。
  final bool subdued;

  /// 玻璃条里的单格尺寸：标题栏条高 56，上下各留 6。
  ///
  /// 44 是 iOS 的最小触控尺寸；比 48 小一档，但标题栏里的图标不该把标题挤没。
  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    final colors = GlassControlColors.resolve(
      context,
      selected: selected,
      subdued: subdued,
    );
    final motion = AppMotion.of(context);

    void handleTap() {
      unawaited(AppHaptics.selection());
      onPressed();
    }

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: handleTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: PressableScale(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: handleTap,
              child: SizedBox(
                width: size,
                height: size,
                child: AnimatedContainer(
                  duration: motion.quick,
                  curve: motion.standardCurve,
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: colors.fill ?? Colors.transparent,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: AppSizes.iconMd,
                      color: colors.foreground,
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
