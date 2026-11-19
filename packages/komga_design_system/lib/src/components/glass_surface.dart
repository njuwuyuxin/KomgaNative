import 'package:komga_design_system/src/components/frosted_surface.dart';
import 'package:komga_design_system/src/materials.dart';
import 'package:material_ui/material_ui.dart';

/// 液态玻璃表面 = 毛玻璃 + 浮层阴影。
///
/// 模糊、底色、反光和描边都在 [FrostedSurface] 里（它们属于材质本身）；
/// 这一层只补两件"浮起来"的事：
/// 1. 给整块形状加 [shadows]（墨水屏自动清空）；
/// 2. 默认外形是胶囊——导航条和搜索圆球都用它，不必每处传 shape。
///
/// 墨水屏：不模糊、不反光、不阴影（`AppMaterial.resolve` / `AppShadows.of`
/// 统一退化），只剩纸色底 + 1px 墨色描边。
///
/// 性能约束与 [FrostedSurface] 相同：内部有一个 `BackdropFilter`，
/// **只用于导航条、chrome、面板这类常驻浮层**，不要放进列表行或网格单元格。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.shape,
    this.kind = AppMaterialKind.bar,
    this.shadows,
    super.key,
  });

  final Widget child;

  /// 外形；为空时是胶囊（导航条 / 搜索圆球都用它）。
  final ShapeBorder? shape;

  /// 取哪种材质；默认 [AppMaterialKind.bar]（玻璃档）。
  final AppMaterialKind kind;

  /// 浮层阴影；为空时按主题取（浅色更淡），墨水屏自动清空。
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final outline = shape ?? const StadiumBorder();
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: outline,
        shadows: shadows == null
            ? AppShadows.floatingOf(context)
            : AppShadows.of(context, shadows!),
      ),
      child: FrostedSurface(kind: kind, shape: outline, child: child),
    );
  }
}
