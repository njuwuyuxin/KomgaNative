import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/page_curl.dart';
import 'package:komga_native/src/widgets/reader_page.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

part 'reader_curl_plan.dart';
part 'reader_page_turn.dart';
part 'reader_zoom.dart';

/// 一次翻页所处的阶段。
enum _TurnPhase { idle, dragging, settling }

/// 单页 / 双页的绘制层。
///
/// 一个"跨页"就是屏幕上要同时显示的那 1–2 页；单页模式只是长度为 1 的特例，
/// 所以缩放、平移、点击区、图片加载都在这里共用一套，不用写两遍。
/// 翻页/进度/模式切换由 `ReaderScreen` 管——这里只负责"把当前的跨页画好"。
///
/// 翻页动画在 `reader_page_turn.dart`：单页模式卷走当前页 / 卷回上一页；
/// 双页模式像真书一样，半边页铰接在书脊上翻过去，纸背就是下一屏的那一页。
/// 纸面位图没就绪、或屏的页数变了（单页↔双页）时退化成平移；单页模式下
/// 底下那一页还在加载**不算**退化——纸掀开后露出的就是它的加载态。
/// 缩放、平移与双击缩放在 `reader_zoom.dart`。
class ReaderPagedView extends ConsumerStatefulWidget {
  const ReaderPagedView({
    required this.bookId,
    required this.pages,
    required this.spread,
    required this.rightToLeft,
    required this.palette,
    required this.onTurn,
    required this.onToggleChrome,
    this.fit = FitMode.contain,
    this.doublePage = false,
    this.nextSpread,
    this.previousSpread,
    this.style = const PageTurnStyle(),
    this.lockZoom = false,
    this.trimBorders = false,
    super.key,
  });

  final String bookId;

  /// 全书页元数据（尺寸未知时按 [kFallbackPageWidth] × [kFallbackPageHeight] 处理）。
  final List<PageInfo> pages;

  /// 当前跨页包含的 **0 基**页索引，1–2 个。
  final List<int> spread;

  final bool rightToLeft;
  final ReaderPalette palette;

  /// 单页适配方式（UI-P1-3）。双页模式下一律按 `contain`，见引擎注释。
  final FitMode fit;

  /// 当前是不是双页模式：决定引擎是否忽略 [fit]（一跨页两页并排，铺满会裁掉另一页）。
  final bool doublePage;

  /// 翻页请求：-1 上一屏，+1 下一屏（由外部决定是"一页"还是"一跨页"）。
  final ValueChanged<int> onTurn;

  final VoidCallback onToggleChrome;

  /// 相邻的跨页：拖动时先画在下面，翻过去才真正换页。
  final List<int>? nextSpread;
  final List<int>? previousSpread;

  final PageTurnStyle style;

  /// 翻页后保持缩放比例（UI-P3-4）。
  final bool lockZoom;

  /// 自动裁掉页图白边（UI-P3-10）。
  final bool trimBorders;

  @override
  ReaderPagedViewState createState() => ReaderPagedViewState();
}

class ReaderPagedViewState extends ConsumerState<ReaderPagedView>
    with TickerProviderStateMixin, _PageTurn, _Zoom {
  // 手势回调里拿不到 LayoutBuilder 的 constraints，所以 build 时缓存一份：
  // 缩放要以焦点为基准，需要"缩放前的有效比例 + 内容左上角"。
  int _pageWidth = kFallbackPageWidth;
  int _pageHeight = kFallbackPageHeight;
  SizeD _viewport = const SizeD(0, 0);

  /// 交给引擎的阅读模式：双页时引擎会忽略 [ReaderPagedView.fit]。
  @override
  ReadingMode get _engineMode =>
      widget.doublePage ? ReadingMode.doublePage : ReadingMode.paged;

  @override
  void didUpdateWidget(ReaderPagedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final spreadChanged = !_sameSpread(oldWidget.spread, widget.spread);
    final layoutChanged =
        oldWidget.fit != widget.fit ||
        oldWidget.doublePage != widget.doublePage;
    if (layoutChanged) {
      // 适配方式/单双页变了，旧缩放/平移不再成立。
      _resetZoom();
    } else if (spreadChanged) {
      if (widget.lockZoom) {
        // 保留缩放倍数，但把位置夹回中间：上一页的平移区间未必还成立。
        setState(() => _pan = Offset.zero);
      } else {
        _resetZoom();
      }
    }
    if (spreadChanged || layoutChanged) _scheduleSheets();
  }

  static bool _sameSpread(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- 布局 ----

  @override
  _SpreadFrame _frameFor(
    List<int> spread,
    SizeD viewport, {
    bool applyZoom = true,
  }) {
    final order = visualOrder(spread, rightToLeft: widget.rightToLeft);
    final sizes = <int, int>{};
    var totalWidth = 0;
    var maxHeight = kFallbackPageHeight;
    for (final index in order) {
      final info = widget.pages[index];
      final w = info.width ?? kFallbackPageWidth;
      sizes[index] = w;
      totalWidth += w;
      final h = info.height ?? kFallbackPageHeight;
      if (h > maxHeight) maxHeight = h;
    }
    if (applyZoom) {
      _pageWidth = totalWidth;
      _pageHeight = maxHeight;
    }
    final layout = computePagedLayout(
      pageWidth: totalWidth,
      pageHeight: maxHeight,
      viewport: viewport,
      fit: widget.fit,
      mode: _engineMode,
      zoomFactor: applyZoom ? _zoom : 1,
      panX: applyZoom ? _pan.dx : 0,
      panY: applyZoom ? _pan.dy : 0,
    );
    final content = Rect.fromLTWH(
      layout.content.left,
      layout.content.top,
      layout.content.width,
      layout.content.height,
    );
    if (applyZoom) {
      // 记住"哪个方向溢出"和"平移能走多远"：手势回调里拿不到 constraints，
      // 而夹紧区间必须和引擎一致，否则会出现拖过头的粘滞。
      _currentScale = layout.scale;
      _contentLeft = content.left;
      _contentTop = content.top;
      _overflowX = content.width > viewport.width + 0.5;
      _overflowY = content.height > viewport.height + 0.5;
      _panMinX = _overflowX ? viewport.width - content.width : 0;
      _panMinY = _overflowY ? viewport.height - content.height : 0;
    }
    // 每页按宽度比例占一格、竖直居中（和 contain 的图严格对齐，卷页起手才不跳）。
    final slots = <int, Rect>{};
    final scale = totalWidth <= 0 ? 0.0 : content.width / totalWidth;
    var left = content.left;
    for (final index in order) {
      final w = sizes[index]! * scale;
      final h = (widget.pages[index].height ?? kFallbackPageHeight) * scale;
      final fitted = h <= 0 || h > content.height ? content.height : h;
      final top = content.top + (content.height - fitted) / 2;
      slots[index] = Rect.fromLTWH(left, top, w, fitted);
      left += w;
    }
    return _SpreadFrame(
      order: order,
      sizes: sizes,
      layout: layout,
      content: content,
      slots: slots,
    );
  }

  @override
  Widget _spreadRow(_SpreadFrame frame) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final index in frame.order)
        Expanded(
          flex: frame.sizes[index]!,
          child: ReaderPage(
            bookId: widget.bookId,
            pageIndex: index,
            palette: widget.palette,
            decodedImage: _sheets.imageFor(index),
            trimBorders: widget.trimBorders,
          ),
        ),
    ],
  );

  @override
  Positioned _positioned(_SpreadFrame frame, Widget child) => Positioned(
    left: frame.content.left,
    top: frame.content.top,
    width: frame.content.width,
    height: frame.content.height,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final turning = _phase != _TurnPhase.idle;
    final neighbour = turning
        ? (_forward ? widget.nextSpread : widget.previousSpread)
        : null;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final viewport = SizeD(constraints.maxWidth, constraints.maxHeight);
        _viewport = viewport;
        final frame = _frameFor(widget.spread, viewport);
        final neighbourFrame = neighbour == null
            ? null
            : _frameFor(neighbour, viewport, applyZoom: false);

        return Listener(
          key: const Key('reader-tap-layer'),
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              children: turning
                  ? _turningLayers(frame, neighbourFrame)
                  : <Widget>[_positioned(frame, _spreadRow(frame))],
            ),
          ),
        );
      },
    );
  }
}
