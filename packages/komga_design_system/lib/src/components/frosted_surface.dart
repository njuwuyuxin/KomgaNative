import 'package:komga_design_system/src/components/glass_optics_layers.dart';
import 'package:komga_design_system/src/components/liquid_glass_shader.dart';
import 'package:komga_design_system/src/materials.dart';
import 'package:material_ui/material_ui.dart';

/// 毛玻璃表面。两条路径：
/// - **着色器版**（液态玻璃档 + Impeller 真机，[LiquidGlassProgram.available]）：
///   轻模糊 → `liquid_glass.frag`（外缘斜面折射 + RGB 色散 + 提饱和 + 柔光 + 方向性高光）；
/// - **合成版**（测试渲染器 / Skia / 着色器加载失败，以及非玻璃档）：
///   裁剪 →（液态玻璃档）外缘折射 → 背景模糊（+ 提饱和）
///   → 半透明底色 → 体内反光 →（液态玻璃档）内缘聚光 + 镜面高光边 + 轮廓 → 描边。
///
/// - 反光来自 [AppMaterial.highlight]，光学层来自 [AppMaterial.optics]：
///   都只给彩色主题的 [AppMaterialKind.bar]（液态玻璃档），压在底色之上、
///   裁剪之内，但**不在**模糊里——模糊只作用于背后已经画好的像素。
/// - 折射**先于**模糊：环带里先把玻璃外的内容拉进来，再整体模糊，接缝被揉平。
///
/// 性能约束：`BackdropFilter` 每帧都要读回背后的像素，**只用于 chrome 和面板**，
/// 不要放进网格单元格或列表行里。液态玻璃档每块多一次背景读取（折射环带）。
///
/// 材质按主题自动退化（见 [AppMaterial.resolve]）；也可以显式传 [material]
/// （阅读器 chrome 永远用深色材质，与系统深浅色无关）。
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    required this.child,
    this.kind = AppMaterialKind.bar,
    this.material,
    this.shape,
    this.opacity = 1,
    super.key,
  });

  final Widget child;
  final AppMaterialKind kind;

  /// 显式指定的材质；为空时按 [kind] 从主题取。
  final AppMaterial? material;

  /// 外形（裁剪 + 描边）；为空时是矩形。
  final ShapeBorder? shape;

  /// 整体可见度（0..1）。
  ///
  /// 毛玻璃做淡入/淡出动画时必须通过本参数控制，**不要**在外面套 `Opacity`：
  /// `Opacity(opacity < 1)` 会创建离屏 `OpacityLayer` 隔断 `BackdropFilter`
  /// 读取屏幕背景，动画结束 `opacity == 1` 撤掉离屏层时会从实心色块跳变成玻璃。
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final effectiveOpacity = opacity.clamp(0.0, 1.0);
    final resolved = material ?? AppMaterial.of(context, kind);
    final border = resolved.border;
    final outline = shape ?? const RoundedRectangleBorder();
    final optics = resolved.optics;

    // 内容淡入放在 BackdropFilter / 着色器内部，不隔断外层对屏幕背景的采样。
    final content = effectiveOpacity >= 1
        ? child
        : Opacity(opacity: effectiveOpacity, child: child);

    // 真机（Impeller）：着色器版液态玻璃——底色、折射、色散、高光都在着色器里。
    if (optics != null && LiquidGlassProgram.available) {
      return LiquidGlassShaderSurface(
        params: optics.shader,
        shape: outline,
        opacity: effectiveOpacity,
        child: content,
      );
    }

    final tint = effectiveOpacity >= 1
        ? resolved.tint
        : resolved.tint.withValues(alpha: resolved.tint.a * effectiveOpacity);
    final effectiveBorder = border == null || effectiveOpacity >= 1
        ? border
        : border.copyWith(
            color: border.color.withValues(
              alpha: border.color.a * effectiveOpacity,
            ),
          );

    Widget surface = DecoratedBox(
      decoration: ShapeDecoration(
        color: tint,
        shape: effectiveBorder == null
            ? outline
            : (outline is OutlinedBorder
                  ? outline.copyWith(side: effectiveBorder)
                  : outline),
      ),
      child: content,
    );

    final highlight = resolved.highlight;
    if (highlight != null || optics != null) {
      Widget? highlightLayer = highlight == null
          ? null
          : DecoratedBox(
              decoration: ShapeDecoration(shape: outline, gradient: highlight),
            );
      Widget? lightLayer = optics == null
          ? null
          : CustomPaint(
              painter: GlassLightPainter(optics: optics, shape: outline),
            );
      if (effectiveOpacity < 1) {
        if (highlightLayer != null) {
          highlightLayer = Opacity(
            opacity: effectiveOpacity,
            child: highlightLayer,
          );
        }
        if (lightLayer != null) {
          lightLayer = Opacity(opacity: effectiveOpacity, child: lightLayer);
        }
      }
      surface = Stack(
        // passthrough：由玻璃里的内容决定尺寸，光学层再铺满它。
        fit: StackFit.passthrough,
        children: <Widget>[
          surface,
          if (highlightLayer != null)
            Positioned.fill(child: IgnorePointer(child: highlightLayer)),
          if (lightLayer != null)
            Positioned.fill(child: IgnorePointer(child: lightLayer)),
        ],
      );
    }

    final filter = resolved.filterForOpacity(effectiveOpacity);
    if (filter != null) {
      surface = BackdropFilter(filter: filter, child: surface);
      if (optics != null && optics.refracts && effectiveOpacity > 0.01) {
        surface = Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            // 先画：模糊层读到的背景已经是折射过的。
            Positioned.fill(
              child: GlassRefraction(
                optics: optics,
                shape: outline,
                strength: effectiveOpacity,
              ),
            ),
            surface,
          ],
        );
      }
    }
    return ClipPath(
      clipper: ShapeBorderClipper(shape: outline),
      child: surface,
    );
  }
}
