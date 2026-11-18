import 'dart:ui' as ui;

import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 翻页动画的绘制层。
///
/// 三种效果，从"最真"到"最省"：
/// - [PageTurnEffect.curl]：片元着色器把纸面卷起来（需要快照，见 `ReaderPagedView`）；
/// - [PageTurnEffect.slide]：整张纸平移出去（双页模式、着色器不可用时用）；
/// - [PageTurnEffect.none]：不做动画（墨水屏），直接换页。
enum PageTurnEffect { curl, slide, none }

/// 一次翻页的手感参数。
///
/// 时长先写死 400ms（用户要求 0.3–0.5s），后续做进 `ReaderPrefs` 变成可配置。
class PageTurnStyle {
  const PageTurnStyle({
    this.effect = PageTurnEffect.curl,
    this.duration = const Duration(milliseconds: 400),
  });

  final PageTurnEffect effect;
  final Duration duration;

  bool get animates => effect != PageTurnEffect.none;
}

/// 加载并缓存 `shaders/page_curl.frag`。
///
/// 只加载一次；失败（老设备/打包漏了 shader）时所有翻页自动降级成平移，
/// 不抛错、不打断阅读。
class PageCurlProgram {
  PageCurlProgram._();

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  /// 已加载的程序；还没加载或加载失败时返回 null。
  static ui.FragmentProgram? get program => _program;

  static Future<void> ensureLoaded() {
    if (_program != null) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<ui.FragmentProgram?> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(
        'shaders/page_curl.frag',
      );
      _program = program;
      return program;
    } on Object {
      // 拿不到着色器就退回平移：翻页动画是锦上添花，不能让它打断阅读。
      return null;
    }
  }
}

/// 把一帧纸面快照按 [geometry] 画出来。整块画布交给着色器，纸面矩形由 `uRect` 指定。
class PageCurlPainter extends CustomPainter {
  const PageCurlPainter({
    required this.sheet,
    required this.sheetRect,
    required this.geometry,
  });

  final ui.Image sheet;

  /// 纸面（页面内容）在画布上的矩形。
  final Rect sheetRect;

  final CurlGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    final program = PageCurlProgram.program;
    if (program == null) return;
    final shader = program.fragmentShader();
    try {
      // 顺序必须与 .frag 里的 uniform 声明一致。
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, sheetRect.left)
        ..setFloat(3, sheetRect.top)
        ..setFloat(4, sheetRect.width)
        ..setFloat(5, sheetRect.height)
        ..setFloat(6, geometry.foldX + sheetRect.left)
        ..setFloat(7, geometry.foldY + sheetRect.top)
        ..setFloat(8, geometry.normalX)
        ..setFloat(9, geometry.normalY)
        ..setFloat(10, geometry.radius)
        ..setFloat(11, geometry.progress)
        ..setFloat(12, geometry.cornerX + sheetRect.left)
        ..setFloat(13, geometry.cornerY + sheetRect.top)
        ..setFloat(14, geometry.coneLength)
        ..setFloat(15, geometry.bend)
        ..setImageSampler(0, sheet);

      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = shader
          ..isAntiAlias = false,
      );
    } finally {
      shader.dispose();
    }
  }

  @override
  bool shouldRepaint(PageCurlPainter oldDelegate) =>
      oldDelegate.sheet != sheet ||
      oldDelegate.geometry.progress != geometry.progress ||
      oldDelegate.geometry.radius != geometry.radius ||
      oldDelegate.geometry.coneLength != geometry.coneLength ||
      oldDelegate.sheetRect != sheetRect ||
      oldDelegate.geometry.mirrored != geometry.mirrored;
}
