import 'package:yomu_design_system/src/motion.dart';
import 'package:yomu_design_system/src/themes.dart';
import 'package:yomu_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 多选态的圆形勾选指示器：未选为空心环，选中为主色实心圆 + 白色对勾。
///
/// [onCover] 为 true 时叠在封面图上：未选态带一层轻烟熏半透明底与白环，
/// 选中态带白边与轻投影，确保在纯白、纯黑及与品牌色接近的封面上都能清晰分离。
/// 墨水屏退化为纯黑白高对比圆环/实心圆，无阴影、无动画。
class SelectionBadge extends StatelessWidget {
  const SelectionBadge({
    required this.selected,
    this.onCover = false,
    super.key,
  });

  final bool selected;
  final bool onCover;

  static const Color _coverUnselectedFill = Color(0x47000000);
  static const Color _coverUnselectedRing = Color(0xEBFFFFFF);
  static const List<BoxShadow> _coverSelectedShadow = <BoxShadow>[
    BoxShadow(color: Color(0x3D000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> _coverUnselectedShadow = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final eink = AppTheme.isEink(theme);
    final motion = AppMotion.of(context);

    final Color fill;
    final Border? border;
    final List<BoxShadow>? shadows;

    if (selected) {
      fill = eink ? AppTheme.einkInk : scheme.primary;
      border = onCover
          ? Border.all(
              color: eink ? AppTheme.einkPaper : Colors.white,
              width: AppSpacing.xxs,
            )
          : null;
      shadows = (!eink && onCover) ? _coverSelectedShadow : null;
    } else if (onCover) {
      fill = eink ? AppTheme.einkPaper : _coverUnselectedFill;
      border = Border.all(
        color: eink ? AppTheme.einkInk : _coverUnselectedRing,
        width: 1.5,
      );
      shadows = eink ? null : _coverUnselectedShadow;
    } else {
      fill = eink ? AppTheme.einkPaper : Colors.transparent;
      border = Border.all(
        color: eink ? AppTheme.einkInk : scheme.outline.withValues(alpha: 0.7),
        width: 1.5,
      );
      shadows = null;
    }

    return AnimatedContainer(
      duration: motion.quick,
      curve: motion.standardCurve,
      width: AppSizes.iconLg,
      height: AppSizes.iconLg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: border,
        boxShadow: shadows,
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: motion.quick,
        switchInCurve: motion.emphasizedCurve,
        switchOutCurve: motion.exitCurve,
        transitionBuilder: (Widget child, Animation<double> animation) =>
            FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.5, end: 1.0).animate(animation),
                child: child,
              ),
            ),
        child: selected
            ? Icon(
                Icons.check_rounded,
                key: const ValueKey<bool>(true),
                size: AppSizes.iconXs,
                color: eink ? AppTheme.einkPaper : scheme.onPrimary,
              )
            : const SizedBox.shrink(key: ValueKey<bool>(false)),
      ),
    );
  }
}
