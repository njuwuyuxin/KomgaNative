import 'package:komga_design_system/src/materials.dart';
import 'package:komga_design_system/src/themes.dart';
import 'package:material_ui/material_ui.dart';

/// 玻璃控件的前景色与"选中嵌入胶囊"底色。
///
/// 与底部导航条同一套规则（`floating_nav_bar.dart` 的 `_navColors`）：
/// iOS 26 的玻璃控件选中时是玻璃里再嵌一块**中性**亮/暗胶囊，
/// 只有图标与文字用主色——整块铺主色会把玻璃染成塑料。
/// 墨水屏反过来（墨底纸白），灰阶上才认得出来。
@immutable
class GlassControlColors {
  const GlassControlColors({required this.foreground, this.fill});

  final Color foreground;
  final Color? fill;

  /// [subdued] 用于未选中项：比主前景低一档，避免一排图标抢标题。
  static GlassControlColors resolve(
    BuildContext context, {
    bool selected = false,
    bool subdued = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (AppTheme.isEink(theme)) {
      return selected
          ? const GlassControlColors(
              foreground: AppTheme.einkPaper,
              fill: AppTheme.einkInk,
            )
          : const GlassControlColors(foreground: AppTheme.einkInk);
    }
    final optics = AppMaterial.resolve(
      AppMaterialKind.bar,
      eink: false,
      dark: theme.brightness == Brightness.dark,
    ).optics;
    return GlassControlColors(
      foreground: selected
          ? scheme.primary
          : (subdued ? scheme.onSurfaceVariant : scheme.onSurface),
      fill: selected ? optics?.selectionFill : null,
    );
  }
}
