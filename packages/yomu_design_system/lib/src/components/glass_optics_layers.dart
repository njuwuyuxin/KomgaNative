import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show BackdropFilterLayer;
import 'package:yomu_design_system/src/glass_optics.dart';
import 'package:material_ui/material_ui.dart';

/// 液态玻璃的两块"光学"零件，由 `FrostedSurface` 组装：
/// - [GlassRefraction]：外缘环带里的折射（把玻璃外的内容拉进来）；
/// - [GlassLightPainter]：内缘聚光 + 方向性镜面高光边 + 轮廓线。
///
/// 都只在彩色主题的玻璃档出现，墨水屏不会建出来。

/// 外缘环带折射。
///
/// 做法：一个只在**环带**（外形减去内缩 [GlassOptics.refractionBand] 的外形）
/// 里生效的背景滤镜，以玻璃中心为原点把背后的内容**缩小**——于是外缘那一像素
/// 显示的是玻璃外 [GlassOptics.refraction] 远处的内容，越往里偏移越小，
/// 环带以内完全不动。随后整块玻璃的模糊会把环带内外的接缝揉平。
///
/// 为什么要自己写 render object：缩放矩阵必须以"玻璃中心在当前图层里的位置"
/// 为原点，这个位置只有 paint 时才知道（滚动、按下缩放都会变）。
class GlassRefraction extends StatelessWidget {
  const GlassRefraction({
    required this.optics,
    required this.shape,
    this.strength = 1,
    super.key,
  });

  final GlassOptics optics;
  final ShapeBorder shape;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipPath(
        clipper: _RingClipper(shape: shape, band: optics.refractionBand),
        child: _Lens(pull: optics.refraction * strength.clamp(0.0, 1.0)),
      ),
    );
  }
}

/// 外形减去内缩后的外形：一圈环带。
class _RingClipper extends CustomClipper<Path> {
  const _RingClipper({required this.shape, required this.band});

  final ShapeBorder shape;
  final double band;

  @override
  Path getClip(Size size) {
    final outer = Offset.zero & size;
    final inner = outer.deflate(band);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(shape.getOuterPath(outer), Offset.zero);
    if (!inner.isEmpty) path.addPath(shape.getOuterPath(inner), Offset.zero);
    return path;
  }

  @override
  bool shouldReclip(_RingClipper oldClipper) =>
      oldClipper.shape != shape || oldClipper.band != band;
}

class _Lens extends LeafRenderObjectWidget {
  const _Lens({required this.pull});

  final double pull;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLens(pull: pull);

  @override
  void updateRenderObject(BuildContext context, _RenderLens renderObject) {
    renderObject.pull = pull;
  }
}

class _RenderLens extends RenderBox {
  _RenderLens({required double pull}) : _pull = pull;

  double get pull => _pull;
  double _pull;
  set pull(double value) {
    if (value == _pull) return;
    _pull = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final center = offset + size.center(Offset.zero);
    // 外缘到中心的半宽 h，在外缘采样 h + pull 处 → 缩放 h / (h + pull)。
    final sx = (size.width / 2) / (size.width / 2 + pull);
    final sy = (size.height / 2) / (size.height / 2 + pull);
    final matrix = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
    context.pushLayer(
      BackdropFilterLayer(
        filter: ui.ImageFilter.matrix(
          matrix.storage,
          filterQuality: FilterQuality.medium,
        ),
      ),
      (PaintingContext context, Offset offset) {},
      offset,
    );
  }
}

/// 玻璃自己的光：内缘聚光、方向性镜面高光边、轮廓线。
///
/// 三者都"骑"在外轮廓上：描边宽度取两倍，外侧那一半被外层裁剪吃掉，
/// 剩下的正好贴着内缘——不用自己算内缩路径，任意 [ShapeBorder] 都成立。
class GlassLightPainter extends CustomPainter {
  const GlassLightPainter({required this.optics, required this.shape});

  final GlassOptics optics;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final outline = shape.getOuterPath(rect);

    // 1. 内缘聚光：一圈向内渗的柔光（厚玻璃把光聚在边上）。
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = optics.rimWidth * 2
        ..color = optics.rimLight
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, optics.rimWidth / 2),
    );

    // 2. 镜面高光边：亮度随方向变（左上主光、右下反射）。
    final stops = <double>[
      for (var i = 0; i < GlassOptics.specularStops; i++)
        i / (GlassOptics.specularStops - 1),
    ];
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = optics.specularWidth * 2
        ..shader = SweepGradient(
          colors: optics.specular,
          stops: stops,
        ).createShader(rect),
    );

    // 3. 轮廓：一丝暗线，浅色背景上把玻璃托出来。
    final contour = optics.contour;
    if (contour != null) {
      canvas.drawPath(
        outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = contour,
      );
    }
  }

  @override
  bool shouldRepaint(GlassLightPainter oldDelegate) =>
      oldDelegate.optics != optics || oldDelegate.shape != shape;
}
