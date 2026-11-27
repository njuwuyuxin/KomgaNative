import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:yomu_design_system/src/glass_optics.dart';
import 'package:material_ui/material_ui.dart';

/// 加载并缓存液态玻璃着色器（`shaders/liquid_glass.frag`）。
///
/// 只在 Impeller 上可用（`ImageFilter.shader` 的限制）；测试渲染器、Skia 后端、
/// 加载失败时 [available] 为 false，`FrostedSurface` 退回合成版玻璃。
abstract final class LiquidGlassProgram {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// 能不能走着色器路径。
  static bool get available =>
      _program != null && ui.ImageFilter.isShaderFilterSupported;

  static ui.FragmentProgram? get program => _program;

  /// 启动时调用一次（`main()` 里 `runApp` 之前）；失败静默降级。
  static Future<void> ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    try {
      _program = await ui.FragmentProgram.fromAsset(
        'packages/yomu_design_system/shaders/liquid_glass.frag',
      );
    } on Exception catch (error) {
      // 玻璃是装饰：拿不到着色器就用合成版，不打断启动。
      debugPrint('LiquidGlassProgram: fallback to composited glass ($error)');
    } on FlutterError catch (error) {
      debugPrint('LiquidGlassProgram: fallback to composited glass ($error)');
    }
  }
}

/// 着色器版液态玻璃：外缘斜面折射 + RGB 色散 + 提饱和 + 斜面柔光 + 方向性镜面高光。
///
/// 结构：裁剪 → 单层着色器背景滤镜（轻模糊也在着色器里）→ 内容。
/// 由 `FrostedSurface` 在 [LiquidGlassProgram.available] 时选用。
class LiquidGlassShaderSurface extends StatelessWidget {
  const LiquidGlassShaderSurface({
    required this.params,
    required this.shape,
    required this.child,
    this.opacity = 1,
    super.key,
  });

  final LiquidShaderParams params;
  final ShapeBorder shape;
  final Widget child;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: _LiquidLens(
        params: params,
        shape: shape,
        devicePixelRatio: dpr,
        opacity: opacity.clamp(0.0, 1.0),
        child: child,
      ),
    );
  }
}

class _LiquidLens extends SingleChildRenderObjectWidget {
  const _LiquidLens({
    required this.params,
    required this.shape,
    required this.devicePixelRatio,
    required this.opacity,
    super.child,
  });

  final LiquidShaderParams params;
  final ShapeBorder shape;
  final double devicePixelRatio;
  final double opacity;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLiquidLens(
    params: params,
    shape: shape,
    devicePixelRatio: devicePixelRatio,
    opacity: opacity,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidLens renderObject,
  ) {
    renderObject
      ..params = params
      ..shape = shape
      ..devicePixelRatio = devicePixelRatio
      ..opacity = opacity;
  }
}

class _RenderLiquidLens extends RenderProxyBox {
  _RenderLiquidLens({
    required LiquidShaderParams params,
    required ShapeBorder shape,
    required double devicePixelRatio,
    required double opacity,
  }) : _params = params,
       _shape = shape,
       _dpr = devicePixelRatio,
       _opacity = opacity;

  LiquidShaderParams _params;
  set params(LiquidShaderParams value) {
    if (value == _params) return;
    _params = value;
    markNeedsPaint();
  }

  ShapeBorder _shape;
  set shape(ShapeBorder value) {
    if (value == _shape) return;
    _shape = value;
    markNeedsPaint();
  }

  double _dpr;
  set devicePixelRatio(double value) {
    if (value == _dpr) return;
    _dpr = value;
    markNeedsPaint();
  }

  double _opacity;
  set opacity(double value) {
    if (value == _opacity) return;
    _opacity = value;
    markNeedsPaint();
  }

  /// 上一次 paint 时玻璃在屏幕上的逻辑矩形。
  Rect? _paintedRect;
  bool _watching = false;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  BackdropFilterLayer? get layer => super.layer as BackdropFilterLayer?;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _watching = true;
    SchedulerBinding.instance.addPostFrameCallback(_checkMoved);
  }

  @override
  void detach() {
    _watching = false;
    super.detach();
  }

  /// 着色器坐标是屏幕像素：祖先在**不重绘我**的情况下挪动了我（转场把整页
  /// 当作一个图层平移、外层 repaint boundary 改了 offset），uniform 就过期了。
  /// 每帧结束时比一下屏幕位置，变了就补画一帧（滞后一帧，肉眼看不出）。
  /// 只挂在已有的帧上，不会自己制造帧。
  void _checkMoved(Duration _) {
    if (!_watching || !attached) return;
    if (hasSize && _paintedRect != null && _globalRect() != _paintedRect) {
      markNeedsPaint();
    }
    SchedulerBinding.instance.addPostFrameCallback(_checkMoved);
  }

  Rect _globalRect() =>
      MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);

  @override
  void paint(PaintingContext context, Offset offset) {
    final program = LiquidGlassProgram.program;
    if (program == null || size.isEmpty) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final global = _globalRect();
    _paintedRect = global;
    // 屏幕上的缩放（按下回弹的 Transform.scale）：半径、斜面一起缩。
    final scale = size.width > 0 ? global.width / size.width : 1.0;
    final px = _dpr * scale;
    final p = _params;
    final tint = p.tint;
    // 每帧新建：已提交给光栅线程的旧帧仍持有它自己的 uniform，不能就地改。
    final shader = program.fragmentShader()
      ..setFloat(2, global.left * _dpr)
      ..setFloat(3, global.top * _dpr)
      ..setFloat(4, global.width * _dpr)
      ..setFloat(5, global.height * _dpr)
      ..setFloat(6, _cornerRadius(_shape, size) * px)
      ..setFloat(7, p.bezel * px)
      ..setFloat(8, p.refraction * px)
      ..setFloat(9, p.chromaticAberration)
      ..setFloat(10, p.saturation)
      ..setFloat(11, p.brightness)
      ..setFloat(12, tint.r)
      ..setFloat(13, tint.g)
      ..setFloat(14, tint.b)
      ..setFloat(15, tint.a)
      ..setFloat(16, p.specular)
      ..setFloat(17, p.rimWidth * px)
      ..setFloat(18, p.glow)
      ..setFloat(19, p.blurSigma * px * _opacity)
      ..setFloat(20, _opacity);
    final filter = ui.ImageFilter.shader(shader);
    final existing = layer;
    if (existing == null) {
      layer = BackdropFilterLayer(filter: filter);
    } else {
      existing.filter = filter;
    }
    context.pushLayer(layer!, super.paint, offset);
  }
}

/// 外形的圆角半径（逻辑像素）：着色器只认"圆角矩形"。
double _cornerRadius(ShapeBorder shape, Size size) {
  final half = size.shortestSide / 2;
  return switch (shape) {
    StadiumBorder() => half,
    RoundedRectangleBorder(:final borderRadius) =>
      borderRadius.resolve(TextDirection.ltr).topLeft.x.clamp(0, half),
    // 连续曲率的视觉圆角约为参数的一半左右（见 AppShapes）。
    ContinuousRectangleBorder(:final borderRadius) =>
      (borderRadius.resolve(TextDirection.ltr).topLeft.x / 2).clamp(0, half),
    _ => 0,
  }.toDouble();
}
