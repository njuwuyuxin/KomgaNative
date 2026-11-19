import 'package:komga_design_system/src/materials.dart';
import 'package:material_ui/material_ui.dart';

/// 毛玻璃表面：裁剪 → 背景模糊 → 半透明底色 → 玻璃反光 →（墨水屏）描边。
///
/// 反光来自 [AppMaterial.highlight]：只有"液态玻璃"档（彩色主题的
/// [AppMaterialKind.bar]）有，压在底色之上、裁剪之内，但**不在**模糊里——
/// 模糊只作用于背后已经画好的像素，反光是这一层自己的高光。
///
/// 性能约束：`BackdropFilter` 每帧都要读回背后的像素，**只用于 chrome 和面板**，
/// 不要放进网格单元格或列表行里。
///
/// 材质按主题自动退化（见 [AppMaterial.resolve]）；也可以显式传 [material]
/// （阅读器 chrome 永远用深色材质，与系统深浅色无关）。
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    required this.child,
    this.kind = AppMaterialKind.bar,
    this.material,
    this.shape,
    super.key,
  });

  final Widget child;
  final AppMaterialKind kind;

  /// 显式指定的材质；为空时按 [kind] 从主题取。
  final AppMaterial? material;

  /// 外形（裁剪 + 描边）；为空时是矩形。
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final resolved = material ?? AppMaterial.of(context, kind);
    final border = resolved.border;
    final outline = shape ?? const RoundedRectangleBorder();
    final tinted = DecoratedBox(
      decoration: ShapeDecoration(
        color: resolved.tint,
        shape: border == null
            ? outline
            : (outline is OutlinedBorder
                  ? outline.copyWith(side: border)
                  : outline),
      ),
      child: child,
    );

    final highlight = resolved.highlight;
    final surface = highlight == null
        ? tinted
        : Stack(
            // passthrough：由玻璃里的内容决定尺寸，反光层再铺满它。
            fit: StackFit.passthrough,
            children: <Widget>[
              tinted,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: outline,
                      gradient: highlight,
                    ),
                  ),
                ),
              ),
            ],
          );

    final filter = resolved.filter;
    if (filter == null) {
      return ClipPath(
        clipper: ShapeBorderClipper(shape: outline),
        child: surface,
      );
    }
    return ClipPath(
      clipper: ShapeBorderClipper(shape: outline),
      child: BackdropFilter(filter: filter, child: surface),
    );
  }
}
