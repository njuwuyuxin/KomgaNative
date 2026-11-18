import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
/// 位图不全或屏的页数变了（单页↔双页）时退化成平移。
class ReaderPagedView extends ConsumerStatefulWidget {
  const ReaderPagedView({
    required this.bookId,
    required this.pages,
    required this.spread,
    required this.rightToLeft,
    required this.palette,
    required this.onTurn,
    required this.onToggleChrome,
    this.nextSpread,
    this.previousSpread,
    this.style = const PageTurnStyle(),
    super.key,
  });

  final String bookId;

  /// 全书页元数据（尺寸未知时按 [kFallbackPageWidth] × [kFallbackPageHeight] 处理）。
  final List<PageInfo> pages;

  /// 当前跨页包含的 **0 基**页索引，1–2 个。
  final List<int> spread;

  final bool rightToLeft;
  final ReaderPalette palette;

  /// 翻页请求：-1 上一屏，+1 下一屏（由外部决定是"一页"还是"一跨页"）。
  final ValueChanged<int> onTurn;

  final VoidCallback onToggleChrome;

  /// 相邻的跨页：拖动时先画在下面，翻过去才真正换页。
  final List<int>? nextSpread;
  final List<int>? previousSpread;

  final PageTurnStyle style;

  @override
  ReaderPagedViewState createState() => ReaderPagedViewState();
}

class ReaderPagedViewState extends ConsumerState<ReaderPagedView>
    with SingleTickerProviderStateMixin, _PageTurn {
  /// 指针移动超过这个距离就不算点击（拖拽/缩放）。
  static const double _tapSlop = 12;

  /// 超过这个横向位移才开始跟手翻页（太小会误吃点击）。
  static const double _dragStartSlop = 14;

  @override
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _startZoom = 1;

  // 手势回调里拿不到 LayoutBuilder 的 constraints，所以 build 时缓存一份：
  // 缩放要以焦点为基准，需要"缩放前的有效比例 + 内容左上角"。
  int _pageWidth = kFallbackPageWidth;
  int _pageHeight = kFallbackPageHeight;
  @override
  SizeD _viewport = const SizeD(0, 0);
  double _startScale = 1;
  Offset _startContent = Offset.zero;

  /// 点击判定用自己的指针记账：`onTapUp` 与 `onScaleStart/Update` 在同一个
  /// gesture arena 里会互相抢，实测 tap 会被 scale 吃掉，翻页完全不响应。
  int _activePointers = 0;
  Offset? _downAt;

  @override
  void didUpdateWidget(ReaderPagedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了一屏就复位：上一屏的缩放/平移套到新页上会看到莫名其妙的位置。
    if (!_sameSpread(oldWidget.spread, widget.spread)) {
      _zoom = 1;
      _pan = Offset.zero;
      _scheduleSheets();
    }
  }

  static bool _sameSpread(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- 手势 ----

  void _onScaleStart(ScaleStartDetails details) {
    _startZoom = _zoom;
    _startFocal = details.localFocalPoint;
    final layout = computePagedLayout(
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      viewport: _viewport,
      zoomFactor: _zoom,
      panX: _pan.dx,
      panY: _pan.dy,
    );
    _startScale = layout.scale;
    _startContent = Offset(layout.content.left, layout.content.top);
    _gestureZoom = details.pointerCount > 1;
    _dragOrigin = details.localFocalPoint;
    _dragCandidate = _canAnimate;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      _gestureZoom = true;
      _dragCandidate = false;
      if (_phase == _TurnPhase.dragging) _cancelDrag();
      _applyZoom(details);
      return;
    }
    if (_phase == _TurnPhase.dragging) {
      _updateDrag(details.localFocalPoint);
      return;
    }
    if (_dragCandidate && !_gestureZoom) {
      final delta = details.localFocalPoint - _dragOrigin;
      if (delta.dx.abs() > _dragStartSlop &&
          delta.dx.abs() > delta.dy.abs() * 1.4) {
        _startDrag(delta.dx, details.localFocalPoint);
        return;
      }
      if (delta.dy.abs() > _dragStartSlop) _dragCandidate = false;
    }
    if (_zoom > 1.0) _applyZoom(details);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _dragCandidate = false;
    _gestureZoom = false;
    if (_phase != _TurnPhase.dragging) return;
    _endDrag(details);
  }

  void _applyZoom(ScaleUpdateDetails details) {
    final nextZoom = (_startZoom * details.scale).clamp(1.0, 4.0);
    if (nextZoom <= 1.0) {
      setState(() {
        _zoom = nextZoom;
        // 缩回适配尺寸时内容居中，旧平移没有意义。
        _pan = Offset.zero;
      });
      return;
    }
    // 先用引擎算出"缩放后的有效比例"，再以两指中点为基准反推新的内容左上角。
    // 直接用 zoomFactor 当比例会忽略夹紧（fit 很小时 max 可能小于 fit*4）。
    final nextScale = computePagedLayout(
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      viewport: _viewport,
      zoomFactor: nextZoom,
    ).scale;
    final origin = zoomAboutFocal(
      contentLeft: _startContent.dx,
      contentTop: _startContent.dy,
      scale: _startScale,
      nextScale: nextScale,
      focalX: _startFocal.dx,
      focalY: _startFocal.dy,
      focalDeltaX: details.localFocalPoint.dx - _startFocal.dx,
      focalDeltaY: details.localFocalPoint.dy - _startFocal.dy,
    );
    setState(() {
      _zoom = nextZoom;
      _pan = Offset(origin.left, origin.top);
    });
  }

  void _onTap(double dx, double width) {
    if (_phase != _TurnPhase.idle) return;
    final fraction = width <= 0 ? 0.5 : dx / width;
    if (fraction < 0.33) {
      // 左侧三分之一：LTR 往回翻，RTL 往前翻（日漫）。
      turn(widget.rightToLeft ? 1 : -1);
    } else if (fraction > 0.67) {
      turn(widget.rightToLeft ? -1 : 1);
    } else {
      widget.onToggleChrome();
    }
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
          onPointerDown: (PointerDownEvent event) {
            _activePointers++;
            _downAt = _activePointers == 1 ? event.localPosition : null;
          },
          onPointerUp: (PointerUpEvent event) {
            if (_activePointers > 0) _activePointers--;
            final down = _downAt;
            _downAt = null;
            if (down == null || _activePointers > 0) return;
            // 移动超过阈值视为拖拽/缩放，不当作翻页点击。
            if ((event.localPosition - down).distance > _tapSlop) return;
            _onTap(down.dx, constraints.maxWidth);
          },
          onPointerCancel: (PointerCancelEvent event) {
            _activePointers = 0;
            _downAt = null;
          },
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
