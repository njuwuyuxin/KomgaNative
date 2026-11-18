import 'dart:ui' as ui;

import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 翻页动画的绘制层。
///
/// 三种效果，从"最真"到"最省"：
/// - [PageTurnEffect.curl]：片元着色器把纸面沿圆柱卷起来（需要页面位图，见 [CurlSheets]）；
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

/// 把一帧纸面位图按 [frame]（圆柱卷页几何）画出来。
///
/// 整块画布交给着色器：卷起的纸、翻过去的背面、投在下层的影子都可能落在
/// 纸面矩形之外，所以不能只画 [sheetRect]。
class PageCurlPainter extends CustomPainter {
  const PageCurlPainter({
    required this.sheet,
    required this.sheetRect,
    required this.frame,
  });

  final ui.Image sheet;

  /// 纸面（页面内容）在画布上的矩形。
  final Rect sheetRect;

  /// 纸面坐标系下的几何（原点是 [sheetRect] 的左上角）。
  final CurlFrame frame;

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
      oldDelegate.sheetRect != sheetRect ||
      oldDelegate.frame.axisX != frame.axisX ||
      oldDelegate.frame.axisY != frame.axisY ||
      oldDelegate.frame.dirX != frame.dirX ||
      oldDelegate.frame.dirY != frame.dirY ||
      oldDelegate.frame.radius != frame.radius;
}

/// 卷页要用的两张位图：当前页（往前翻时卷走它）和上一页（往回翻时把它卷回来）。
///
/// 页图字节本来就在仓库 LRU 里，这里只负责解码与释放。
/// 换掉的位图可能还被上一帧的 raster 线程引用着，立刻 `dispose()` 有时会
/// 闪一帧空白，所以统一等下一帧结束再释放。
class CurlSheets {
  ui.Image? _current;
  ui.Image? _previous;
  int? _currentPage;
  int? _previousPage;
  final List<ui.Image> _retired = <ui.Image>[];

  /// [page] 是当前页（0 基）的位图；不匹配时返回 null。
  ui.Image? currentFor(int page) => _currentPage == page ? _current : null;

  /// [page] 是上一页（0 基）的位图；不匹配时返回 null。
  ui.Image? previousFor(int page) => _previousPage == page ? _previous : null;

  /// 当前要的两页（null 表示不需要），已有的直接复用（往前翻一页后，
  /// 原来的"当前页"正好变成新的"上一页"，不必重新解码）。
  Future<void> ensure({
    required int? current,
    required int? previous,
    required Future<ui.Image?> Function(int page) decode,
    required bool Function() stillWanted,
  }) async {
    final pool = <int, ui.Image>{
      if (_currentPage != null && _current != null) _currentPage!: _current!,
      if (_previousPage != null && _previous != null)
        _previousPage!: _previous!,
    };
    final keep = <int>{?current, ?previous};
    for (final entry in pool.entries) {
      if (!keep.contains(entry.key)) _retire(entry.value);
    }
    _current = current == null ? null : pool[current];
    _currentPage = _current == null ? null : current;
    _previous = previous == null ? null : pool[previous];
    _previousPage = _previous == null ? null : previous;

    if (current != null && _current == null) {
      final image = await decode(current);
      if (image != null && !_adopt(image, stillWanted)) return;
      if (image != null) {
        _retire(_current);
        _current = image;
        _currentPage = current;
      }
    }
    if (previous != null && _previous == null) {
      final image = await decode(previous);
      if (image != null && _adopt(image, stillWanted)) {
        _retire(_previous);
        _previous = image;
        _previousPage = previous;
      }
    }
  }

  bool _adopt(ui.Image image, bool Function() stillWanted) {
    if (stillWanted()) return true;
    image.dispose();
    return false;
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
    _current?.dispose();
    _previous?.dispose();
    _current = null;
    _previous = null;
    _flushRetired();
  }
}
