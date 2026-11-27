import 'dart:ui' as ui;

import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/widgets/curl_sheets.dart';
import 'package:yomu_reader/yomu_reader.dart';
import 'package:material_ui/material_ui.dart';

export 'package:yomu/src/widgets/curl_sheets.dart';

/// 翻页动画的绘制层。
///
/// 四种效果，从"最真"到"最省"：
/// - [PageTurnEffect.curl]：片元着色器把纸面沿圆柱卷起来（需要页面位图，见 [CurlSheets]）；
/// - [PageTurnEffect.slide]：整张纸平移出去；
/// - [PageTurnEffect.fade]：当前屏淡出、露出相邻屏（老设备最省的一种）；
/// - [PageTurnEffect.none]：不做动画（墨水屏 / 减少动态效果），直接换页。
enum PageTurnEffect { curl, slide, fade, none }

/// 一次翻页的手感参数。
///
/// 时长来自设计 token（`AppMotion.emphasized`），由调用方传进来：
/// `PageTurnStyle` 本身不认识 `BuildContext`，纯单测里也能构造。
class PageTurnStyle {
  const PageTurnStyle({
    this.effect = PageTurnEffect.curl,
    this.duration = const Duration(milliseconds: 450),
  });

  final PageTurnEffect effect;
  final Duration duration;

  bool get animates => effect != PageTurnEffect.none;

  /// 按"用户选择 + 当前环境"选风格（RDR-05）。
  ///
  /// 墨水屏、系统"减少动态效果"、或时长被 token 压成 0 时一律瞬切：
  /// 用户选了卷页也不该在墨水屏上播动画（整屏全刷 + 拖影）。
  static PageTurnStyle resolve({
    required ReaderPageTurnChoice choice,
    required bool eink,
    required bool disableAnimations,
    required Duration duration,
  }) {
    if (eink || disableAnimations || duration == Duration.zero) {
      return const PageTurnStyle(effect: PageTurnEffect.none);
    }
    return PageTurnStyle(
      effect: switch (choice) {
        ReaderPageTurnChoice.curl => PageTurnEffect.curl,
        ReaderPageTurnChoice.slide => PageTurnEffect.slide,
        ReaderPageTurnChoice.fade => PageTurnEffect.fade,
        ReaderPageTurnChoice.none => PageTurnEffect.none,
      },
      duration: duration,
    );
  }
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
    } on Exception {
      // 拿不到着色器就退回平移：翻页动画是锦上添花，不能让它打断阅读。
      _loading = null;
      return null;
    } on FlutterError {
      _loading = null;
      return null;
    }
  }
}

/// 把一帧纸面位图按 [frame]（圆柱卷页几何）画出来。
///
/// 整块画布交给着色器：卷起的纸、翻过去的背面、投在下层的影子都可能落在
/// 纸面矩形之外，所以不能只画 [sheetRect]。
class PageCurlPainter extends CustomPainter {
  const PageCurlPainter({
    this.sheet,
    required this.sheetRect,
    Rect? sheetUvRect,
    required this.frame,
    this.back,
    this.backRect = Rect.zero,
    Rect? backUvRect,
    this.spineX = 0,
    bool? hinged,
    this.sheetOpacity = 1,
    this.backOpacity = 1,
    this.paperColor,
  }) : sheetUvRect = sheetUvRect ?? sheetRect,
       backUvRect = backUvRect ?? backRect,
       hinged = hinged ?? back != null,
       assert(sheet != null || back != null);

  /// 纸面的真实页面；双页往回翻且上一屏未就绪时可为 null。
  final ui.Image? sheet;

  /// 被卷起纸面在画布上的几何矩形。
  final Rect sheetRect;

  /// [sheet] 完整纹理对应的画布矩形（宽页对半裁切时为整张宽页矩形）。
  final Rect sheetUvRect;

  /// 纸面坐标系下的几何（原点是 [sheetRect] 的左上角）。
  final CurlFrame frame;

  /// 纸背的真实页面（双页模式）；null 时用纸张底色。
  final ui.Image? back;

  /// [back] 落地后在画布上的裁剪矩形。
  final Rect backRect;

  /// [back] 完整纹理对应的画布矩形（宽页对半裁切时为整张宽页矩形）。
  final Rect backUvRect;

  /// 书脊 x（画布坐标）：纸背沿它镜像。
  final double spineX;

  /// true = 双页铰接书脊：落地帧 `radius == 0` 时仍须绘制平压的纸背。
  final bool hinged;

  /// 纸面图像混合权重（0..1）；冷页在卷动途中加载完成时用于平滑淡入。
  final double sheetOpacity;

  /// 纸背图像混合权重（0..1）；冷页在卷动途中加载完成时用于平滑淡入。
  final double backOpacity;

  /// 缺省纸张底色；null 时取默认暖白纸色 `(0.975, 0.970, 0.955)`。
  final Color? paperColor;

  @override
  void paint(Canvas canvas, Size size) {
    final program = PageCurlProgram.program;
    final fallback = sheet ?? back;
    if (program == null || fallback == null) return;
    final effectiveSheet = sheet == null ? 0.0 : sheetOpacity.clamp(0.0, 1.0);
    final effectiveBack = back == null ? 0.0 : backOpacity.clamp(0.0, 1.0);
    final paperR = paperColor == null ? 0.975 : paperColor!.r;
    final paperG = paperColor == null ? 0.970 : paperColor!.g;
    final paperB = paperColor == null ? 0.955 : paperColor!.b;

    final shader = program.fragmentShader();
    try {
      // 顺序必须与 .frag 里的 uniform 声明严格一致（0..29）。
      shader
        ..setFloat(0, size.width)
        ..setFloat(1, size.height)
        ..setFloat(2, sheetRect.left)
        ..setFloat(3, sheetRect.top)
        ..setFloat(4, sheetRect.width)
        ..setFloat(5, sheetRect.height)
        ..setFloat(6, sheetUvRect.left)
        ..setFloat(7, sheetUvRect.top)
        ..setFloat(8, sheetUvRect.width)
        ..setFloat(9, sheetUvRect.height)
        ..setFloat(10, frame.axisX + sheetRect.left)
        ..setFloat(11, frame.axisY + sheetRect.top)
        ..setFloat(12, frame.dirX)
        ..setFloat(13, frame.dirY)
        ..setFloat(14, frame.radius)
        ..setFloat(15, backRect.left)
        ..setFloat(16, backRect.top)
        ..setFloat(17, backRect.width)
        ..setFloat(18, backRect.height)
        ..setFloat(19, backUvRect.left)
        ..setFloat(20, backUvRect.top)
        ..setFloat(21, backUvRect.width)
        ..setFloat(22, backUvRect.height)
        ..setFloat(23, spineX)
        ..setFloat(24, effectiveBack)
        ..setFloat(25, effectiveSheet)
        ..setFloat(26, hinged ? 1 : 0)
        ..setFloat(27, paperR)
        ..setFloat(28, paperG)
        ..setFloat(29, paperB)
        // 采样器必须绑定；缺省面绑另一张兜底图，着色器按权重混合纸张底色。
        ..setImageSampler(0, sheet ?? fallback)
        ..setImageSampler(1, back ?? fallback);

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
      oldDelegate.back != back ||
      oldDelegate.sheetRect != sheetRect ||
      oldDelegate.sheetUvRect != sheetUvRect ||
      oldDelegate.backRect != backRect ||
      oldDelegate.backUvRect != backUvRect ||
      oldDelegate.spineX != spineX ||
      oldDelegate.hinged != hinged ||
      oldDelegate.sheetOpacity != sheetOpacity ||
      oldDelegate.backOpacity != backOpacity ||
      oldDelegate.paperColor != paperColor ||
      oldDelegate.frame.axisX != frame.axisX ||
      oldDelegate.frame.axisY != frame.axisY ||
      oldDelegate.frame.dirX != frame.dirX ||
      oldDelegate.frame.dirY != frame.dirY ||
      oldDelegate.frame.radius != frame.radius;
}
