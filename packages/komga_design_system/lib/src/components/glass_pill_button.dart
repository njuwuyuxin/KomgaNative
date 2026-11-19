import 'dart:async';

import 'package:komga_design_system/src/components/glass_surface.dart';
import 'package:komga_design_system/src/components/pressable_scale.dart';
import 'package:komga_design_system/src/haptics.dart';
import 'package:komga_design_system/src/materials.dart';
import 'package:komga_design_system/src/shapes.dart';
import 'package:komga_design_system/src/themes.dart';
import 'package:komga_design_system/src/tokens.dart';
import 'package:komga_design_system/src/typography.dart';
import 'package:material_ui/material_ui.dart';

/// 玻璃胶囊主按钮（"继续阅读"、开始阅读、重试、连接）。
///
/// 为什么不直接用 `FilledButton`：页面上其他浮层都是液态玻璃，
/// 一块实心主色塑料会显得突兀。这里和导航条同一材质——玻璃底 + 主色文字；
/// 墨水屏没有彩色可表达层级，反白成墨底纸字（token 退化，调用方不判断）。
class GlassPillButton extends StatelessWidget {
  const GlassPillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 可选前置图标（播放 / 刷新 / 连接）。
  final IconData? icon;

  /// true = 撑满可用宽度（表单里的主按钮）。
  final bool expanded;

  /// true = 显示转圈并屏蔽点击（提交中）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eink = AppTheme.isEink(theme);
    final shape = AppShapes.of(context, AppShapes.bar);
    final foreground = eink ? AppTheme.einkPaper : theme.colorScheme.primary;
    final fill = eink ? AppTheme.einkInk : null;

    void handleTap() {
      if (busy) return;
      final onPressed = this.onPressed;
      if (onPressed == null) return;
      unawaited(AppHaptics.selection());
      onPressed();
    }

    final child = SizedBox(
      height: AppSizes.minTouch,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: shape,
          color: fill ?? Colors.transparent,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (busy)
                SizedBox(
                  width: AppSizes.iconSm,
                  height: AppSizes.iconSm,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              else ...<Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: AppSizes.iconMd, color: foreground),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.of(context).label.copyWith(
                      color: foreground,
                      fontSize: AppTypography.of(context).body.fontSize,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final button = Semantics(
      container: true,
      button: true,
      enabled: onPressed != null && !busy,
      label: label,
      onTap: onPressed == null || busy ? null : handleTap,
      child: ExcludeSemantics(
        child: PressableScale(
          enabled: onPressed != null && !busy,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed == null || busy ? null : handleTap,
            child: GlassSurface(
              shape: shape,
              shadows: AppShadows.card,
              child: child,
            ),
          ),
        ),
      ),
    );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
