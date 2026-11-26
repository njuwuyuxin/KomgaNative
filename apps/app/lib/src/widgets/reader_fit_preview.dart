import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 适配方式的 4 个小示意图（RDR-04）。
///
/// 为什么值得画：`contain` / `cover` / `fitWidth` / `fitHeight` 四个词本身
/// 不直观，尤其"填满屏幕"和"适应宽度"在竖屏上很像。
///
/// 一个诚实的限制：页面的长宽比是固定的，所以在这张小图里
/// "填满屏幕"和"适应宽度"的**裁剪结果**看起来一样（都是横向铺满、纵向被裁）。
/// 真正的差别是"能往哪个方向拖"，所以这两种多画一个方向箭头，
/// 而不是硬编一个不存在的视觉差异。
///
/// 墨水屏只画线框：灰阶屏上填充灰块反而糊成一片。
class ReaderFitPreview extends StatelessWidget {
  const ReaderFitPreview({
    required this.fit,
    required this.palette,
    this.size = const Size(AppSizes.fitPreviewWidth, AppSizes.fitPreviewHeight),
    super.key,
  });

  final ReaderFitChoice fit;
  final ReaderPalette palette;
  final Size size;

  @override
  Widget build(BuildContext context) {
    // 页面按 2:3 画。
    const aspect = 2 / 3;
    // 基准：高度铺满时的页面尺寸。
    final fittedW = size.height * aspect;
    final (double w, double h) = switch (fit) {
      ReaderFitChoice.contain ||
      ReaderFitChoice.fitHeight => (fittedW, size.height),
      // 铺满/铺宽：宽度撑满，高度溢出（上下被裁）。
      ReaderFitChoice.cover ||
      ReaderFitChoice.fitWidth => (size.width, size.width / aspect),
    };
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2;

    final line = palette.isEink
        ? Border.all(color: palette.muted)
        : Border.all(color: palette.foreground.withValues(alpha: 0.5));
    final pageDecoration = BoxDecoration(
      color: palette.isEink ? null : palette.foreground.withValues(alpha: 0.22),
      border: line,
    );

    // 可拖动的方向：只有两种"铺满"会在某个方向上溢出。
    final dragIcon = switch (fit) {
      ReaderFitChoice.fitWidth => Icons.swap_vert,
      ReaderFitChoice.fitHeight => Icons.swap_horiz,
      _ => null,
    };

    return ClipRect(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: palette.outline)),
          child: Stack(
            children: <Widget>[
              Positioned(
                left: left,
                top: top,
                width: w,
                height: h,
                child: DecoratedBox(decoration: pageDecoration),
              ),
              if (dragIcon != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Icon(
                    dragIcon,
                    size: AppSizes.iconXs,
                    color: palette.foreground,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
