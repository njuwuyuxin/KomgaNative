import 'dart:ui' as ui;

import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

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
    } on Object {
      // 拿不到着色器就退回平移：翻页动画是锦上添花，不能让它打断阅读。
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
    required this.sheet,
    required this.sheetRect,
    required this.frame,
    this.back,
    this.backRect = Rect.zero,
    this.spineX = 0,
  });

  final ui.Image sheet;

  /// 纸面（页面内容）在画布上的矩形。
  final Rect sheetRect;

  /// 纸面坐标系下的几何（原点是 [sheetRect] 的左上角）。
  final CurlFrame frame;

  /// 纸背的真实页面（双页模式）；null 时纸背是白纸。
  final ui.Image? back;

  /// [back] 落地后在画布上的矩形。
  final Rect backRect;

  /// 书脊 x（画布坐标）：纸背沿它镜像。
  final double spineX;

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
        ..setFloat(6, frame.axisX + sheetRect.left)
        ..setFloat(7, frame.axisY + sheetRect.top)
        ..setFloat(8, frame.dirX)
        ..setFloat(9, frame.dirY)
        ..setFloat(10, frame.radius)
        ..setFloat(11, backRect.left)
        ..setFloat(12, backRect.top)
        ..setFloat(13, backRect.width)
        ..setFloat(14, backRect.height)
        ..setFloat(15, spineX)
        ..setFloat(16, back == null ? 0 : 1)
        ..setImageSampler(0, sheet)
        // 采样器必须绑定；没有纸背时绑同一张图，着色器按 uHasBack 不用它。
        ..setImageSampler(1, back ?? sheet);

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
      oldDelegate.backRect != backRect ||
      oldDelegate.spineX != spineX ||
      oldDelegate.frame.axisX != frame.axisX ||
      oldDelegate.frame.axisY != frame.axisY ||
      oldDelegate.frame.dirX != frame.dirX ||
      oldDelegate.frame.dirY != frame.dirY ||
      oldDelegate.frame.radius != frame.radius;
}

/// 卷页要用的位图，按页（0 基）索引。
///
/// 单页：当前页（往前翻卷走它）、上一页（往回翻把它卷回来）；
/// 双页：两个方向各自要卷的半页 + 它们的纸背。
/// 页图字节本来就在仓库 LRU 里，这里只负责解码与释放；翻一页后
/// 仍然需要的位图直接复用，不重新解码。
/// 换掉的位图可能还被上一帧的 raster 线程引用着，立刻 `dispose()` 有时会
/// 闪一帧空白，所以统一等下一帧结束再释放。
class CurlSheets {
  final Map<int, ui.Image> _images = <int, ui.Image>{};
  final List<ui.Image> _retired = <ui.Image>[];
  final Map<int, Future<void>> _pending = <int, Future<void>>{};
  Set<int> _wanted = <int>{};
  bool Function() _stillWanted = () => false;
  bool _disposed = false;

  /// 第 [page] 页的位图；还没解码好时为 null。
  ui.Image? imageFor(int page) => _images[page];

  /// 只保留 [pages]，缺的逐张解码；[stillWanted] 为 false 说明已经换屏，丢弃结果。
  Future<void> ensure({
    required Set<int> pages,
    required Future<ui.Image?> Function(int page) decode,
    required bool Function() stillWanted,
  }) async {
    if (_disposed || !stillWanted()) return;
    _wanted = Set<int>.of(pages);
    _stillWanted = stillWanted;
    for (final page in _images.keys.toList()) {
      if (!_wanted.contains(page)) _retire(_images.remove(page));
    }
    for (final page in pages) {
      if (_disposed || !stillWanted()) return;
      if (_images.containsKey(page)) continue;
      // 动画完成和 didUpdateWidget 都会排预加载；合并同页解码，避免替换
      // 正被 ReaderPage 借用的位图（或把刚解好的那一张释放掉）。
      await (_pending[page] ??= _decodeAndAdopt(page, decode));
    }
  }

  Future<void> _decodeAndAdopt(
    int page,
    Future<ui.Image?> Function(int page) decode,
  ) async {
    try {
      final image = await decode(page);
      if (image == null) return;
      if (_disposed || !_wanted.contains(page) || !_stillWanted()) {
        image.dispose();
        return;
      }
      _images[page] = image;
    } finally {
      _pending.remove(page)?.ignore();
    }
  }

  void _retire(ui.Image? image) {
    if (image == null) return;
    _retired.add(image);
    WidgetsBinding.instance.addPostFrameCallback((_) => _flushRetired());
  }

  void _flushRetired() {
    for (final image in _retired) {
      image.dispose();
    }
    _retired.clear();
  }

  void dispose() {
    _disposed = true;
    _wanted.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _flushRetired();
  }
}
