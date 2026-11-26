import 'package:yomu_design_system/src/shapes.dart';
import 'package:yomu_design_system/src/themes.dart';
import 'package:yomu_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// iOS 的"inset grouped"分组卡片：一组行放在一块圆角表面里，行间细分割线。
///
/// 为什么需要它：设置页、收藏集、下载页都是"若干行 + 分组说明"，
/// 之前每页各自写 `ListTile` + `Divider`，行是通栏铺满的安卓样式。
/// 现在统一成一张浮在页面上的圆角卡（左右留白 16），分组说明留在卡外。
///
/// 不用玻璃：卡片在滚动流里，而且一组可能十几行——每行一次 `BackdropFilter`
/// 会直接拖垮滚动帧率（见 docs/design-system.md 的性能约束）。
/// 墨水屏：纸底 + 1px 墨框、零圆角，与其它退化保持一致。
class AppListGroup extends StatelessWidget {
  const AppListGroup({
    required this.children,
    this.header,
    this.footer,
    super.key,
  });

  /// 组内各行（`ListTile` / `SwitchListTile` / 自定义行）。
  final List<Widget> children;

  /// 卡外上方的分组说明（大写小字，iOS 风格）。
  final String? header;

  /// 卡外下方的补充说明。
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eink = AppTheme.isEink(theme);
    final scheme = theme.colorScheme;
    final base = AppShapes.of(context, AppShapes.panel);
    final outlined = base is OutlinedBorder
        ? base
        : const RoundedRectangleBorder();
    final shape = outlined.copyWith(
      side: eink ? const BorderSide(color: AppTheme.einkInk) : BorderSide.none,
    );
    final muted = scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                header!.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: muted,
                ),
              ),
            ),
          Material(
            color: eink ? AppTheme.einkPaper : scheme.surfaceContainerLow,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: AppSizes.hairline,
                      thickness: AppSizes.hairline,
                      indent: AppSpacing.md,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                0,
              ),
              child: Text(
                footer!,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}
