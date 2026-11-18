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

/// 一次翻页所处的阶段。
enum _TurnPhase { idle, dragging, settling }

/// 一屏（1–2 页）的绘制矩形与页序。
class _SpreadFrame {
  const _SpreadFrame({
    required this.order,
    required this.sizes,
    required this.layout,
    required this.content,
  });

  final List<int> order;
  final Map<int, int> sizes;
  final PagedLayout layout;
  final Rect content;
}

/// 单页 / 双页的绘制层。
///
/// 一个"跨页"就是屏幕上要同时显示的那 1–2 页；单页模式只是长度为 1 的特例，
/// 所以缩放、平移、点击区、图片加载都在这里共用一套，不用写两遍。
/// 翻页/进度/模式切换由 `ReaderScreen` 管——这里只负责"把当前的跨页画好"。
///
/// 翻页动画也在这里：单页模式用圆柱卷页（`page_curl.dart` + 着色器），
/// 往前翻卷走当前页、往回翻把上一页卷回来；双页/无位图时退化成平移。
/// 位图只在空闲时解码，所以开始拖的那一刻就有图可用。
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
    with SingleTickerProviderStateMixin {
  /// 指针移动超过这个距离就不算点击（拖拽/缩放）。
  static const double _tapSlop = 12;

  /// 超过这个横向位移才开始跟手翻页（太小会误吃点击）。
  static const double _dragStartSlop = 14;

  double _zoom = 1;
  Offset _pan = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _startZoom = 1;

  // 手势回调里拿不到 LayoutBuilder 的 constraints，所以 build 时缓存一份：
  // 缩放要以焦点为基准，需要"缩放前的有效比例 + 内容左上角"。
  int _pageWidth = kFallbackPageWidth;
  int _pageHeight = kFallbackPageHeight;
  SizeD _viewport = const SizeD(0, 0);
  double _startScale = 1;
  Offset _startContent = Offset.zero;

  /// 点击判定用自己的指针记账：`onTapUp` 与 `onScaleStart/Update` 在同一个
  /// gesture arena 里会互相抢，实测 tap 会被 scale 吃掉，翻页完全不响应。
  int _activePointers = 0;
  Offset? _downAt;

  // ---- 翻页动画 ----
  late final AnimationController _turnController;
  _TurnPhase _phase = _TurnPhase.idle;
  bool _forward = true;
  bool _commit = false;
  bool _gestureZoom = false;
  bool _dragCandidate = false;
  Offset _dragOrigin = Offset.zero;

  /// 翻页进度（0..1）：松手判定、平移效果、测试都看它。
  ///
  /// 跟手时等于"拖过的横向距离 / 视口宽"，与卷页的手指位置是两回事——
  /// 卷页时纸的角跟着手指走，整张纸翻走要拖约两倍页宽，不能拿它判定。
  double _progress = 0;

  /// 本次翻动用不用卷页（开始时定下来，翻动途中位图到了也不切换）。
  bool _curl = false;

  /// 卷页时被捏住的角所在位置（标准形纸面坐标，见 `curl_motion.dart`）。
  ({double x, double y}) _finger = (x: 0, y: 0);

  /// 补完动画的起点：松手时的手指位置与进度。
  ({double x, double y}) _settleFrom = (x: 0, y: 0);
  double _settleFromProgress = 0;
  double _settleTarget = 0;
  Curve _settleCurve = Curves.easeOutCubic;

  /// 卷页用的位图：当前页（往前翻）和上一页（往回翻，把它卷回来）。
  ///
  /// 没用 `RepaintBoundary.toImage()`：它在真机上取不到 layer（null check 崩），
  /// 本地 widget 测试却能跑，属于"测试绿、真机死"。页图字节本来就在仓库 LRU 里，
  /// 自己解成 `ui.Image` 更短也更可控。
  final CurlSheets _sheets = CurlSheets();

  @override
  void initState() {
    super.initState();
    _turnController = AnimationController(
      vsync: this,
      duration: widget.style.duration,
    )..addListener(_onTurnTick);
    _turnController.addStatusListener(_onTurnStatus);
    unawaited(PageCurlProgram.ensureLoaded());
    _scheduleSheets();
  }

  @override
  void dispose() {
    _turnController.dispose();
    _sheets.dispose();
    super.dispose();
  }

  /// 由外部（底栏箭头 / 音量键 / 点击）触发的翻页：和拖动走同一套动画。
  ///
  /// 没有位图/不允许动画时直接翻页——宁可瞬切，也不要假装有动画。
  void turn(int delta) {
    if (_phase != _TurnPhase.idle) return;
    final neighbour = delta > 0 ? widget.nextSpread : widget.previousSpread;
    if (neighbour == null || !_canAnimate) {
      widget.onTurn(delta);
      return;
    }
    _begin(forward: delta > 0);
    _commit = true;
    _phase = _TurnPhase.settling;
    setState(() {});
    // 自动翻页：慢起（先掀起页脚）—快—慢收。
    _startSettle(1, widget.style.duration, Curves.easeInOutCubic);
  }

  @visibleForTesting
  double get debugProgress => _progress;

  /// 本次翻动是否在用卷页（否则是平移）。
  @visibleForTesting
  bool get debugCurling => _curl;

  void _begin({required bool forward}) {
    _forward = forward;
    _progress = 0;
    _curl = _curlSheetFor(forward) != null;
    final motion = _motion;
    _finger = motion == null ? (x: 0, y: 0) : motion.fingerAt(0);
  }

  void _onTurnTick() {
    if (!mounted || _phase != _TurnPhase.settling) return;
    final t = _settleCurve.transform(_turnController.value);
    setState(() {
      _progress =
          _settleFromProgress + (_settleTarget - _settleFromProgress) * t;
      final motion = _motion;
      if (motion != null) {
        _finger = motion.settleFinger(
          from: _settleFrom,
          fromTurn: motion.turnOf(_settleFrom),
          toTurn: _settleTarget,
          t: t,
        );
      }
    });
  }

  void _onTurnStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_phase != _TurnPhase.settling) return;
    final commit = _commit;
    _phase = _TurnPhase.idle;
    _commit = false;
    _curl = false;
    _progress = 0;
    _turnController.reset();
    setState(() {});
    if (commit) widget.onTurn(_forward ? 1 : -1);
    _scheduleSheets();
  }

  bool get _canAnimate =>
      widget.style.animates &&
      _phase == _TurnPhase.idle &&
      _zoom <= 1.0 &&
      _viewport.width > 0;

  /// 平移效果的方向：书脊在右边（RTL）时往前翻的纸往右走。
  bool _mirrorFor(bool forward) =>
      forward ? !widget.rightToLeft : widget.rightToLeft;

  /// 卷页的镜像：往前翻和往回翻是同一张纸的正放/倒放，用同一个角。
  ///
  /// RTL（日漫，书脊在右）从左下角掀；LTR（书脊在左）从右下角掀。
  bool get _curlMirrored => !widget.rightToLeft;

  /// 这次翻动要卷的那张纸：往前翻是当前页，往回翻是上一页（单页模式才有）。
  ui.Image? _curlSheetFor(bool forward) {
    if (widget.style.effect != PageTurnEffect.curl) return null;
    if (PageCurlProgram.program == null) return null;
    if (widget.spread.length != 1) return null;
    if (forward) return _sheets.currentFor(widget.spread.first);
    final previous = widget.previousSpread;
    if (previous == null || previous.length != 1) return null;
    return _sheets.previousFor(previous.first);
  }

  /// 被卷那张纸的矩形（画布坐标）：往前翻是当前屏，往回翻是上一屏。
  Rect get _curlRect {
    if (_forward) return _frameFor(widget.spread, _viewport).content;
    final previous = widget.previousSpread;
    if (previous == null) return Rect.zero;
    return _frameFor(previous, _viewport, applyZoom: false).content;
  }

  /// 本次卷页的手指运动；纸面尚未布局时为 null。
  CurlMotion? get _motion {
    final rect = _curlRect;
    if (rect.isEmpty) return null;
    // 卷筒要滑出**屏幕**另一侧，而不是只滑出纸面。
    final exitX = _curlMirrored ? rect.right : _viewport.width - rect.left;
    return CurlMotion(
      forward: _forward,
      width: rect.width,
      height: rect.height,
      exitX: exitX,
    );
  }

  /// 空闲时把当前页和上一页解码成位图，供下一次卷页使用。
  ///
  /// 单页模式才需要（双页走平移）；解码失败就不做卷页，
  /// 自动退化成平移，不打断阅读。
  void _scheduleSheets() {
    if (widget.style.effect != PageTurnEffect.curl) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _phase != _TurnPhase.idle) return;
      final spread = widget.spread;
      final single = spread.length == 1;
      final previous = widget.previousSpread;
      unawaited(
        _sheets.ensure(
          current: single ? spread.first : null,
          previous: single && previous != null && previous.length == 1
              ? previous.first
              : null,
          decode: _decodePage,
          stillWanted: () => mounted && _sameSpread(widget.spread, spread),
        ),
      );
    });
  }

  Future<ui.Image?> _decodePage(int pageIndex) async {
    final repository = ref.read(readerRepositoryProvider);
    final page = pageIndex + 1;
    Uint8List? bytes = repository.cachedPageImage(widget.bookId, page);
    try {
      bytes ??= await repository.pageImage(widget.bookId, page);
    } on ShelfFailure {
      return null;
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

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
    final decision = settlePageTurn(
      progress: _progress,
      velocityX: details.velocity.pixelsPerSecond.dx,
      base: widget.style.duration,
      forwardSign: _dragSign,
    );
    _commit = decision.commit;
    _phase = _TurnPhase.settling;
    // easeOutCubic：尾巴更长、更软，翻页结束时不会"戛然而止"。
    _startSettle(
      decision.commit ? 1 : 0,
      decision.duration,
      Curves.easeOutCubic,
    );
  }

  /// 从**当前位置**补完剩下的动画。
  ///
  /// 控制器每次都从 0 播到 1，起点（松手时的手指与进度）单独记下来插值：
  /// 一是"已经翻了 70%，一松手跳回 0 再重播"这种 bug 从结构上不可能发生，
  /// 二是卷页的手指能沿拱形路径走，而不是直线插值。
  void _startSettle(double target, Duration duration, Curve curve) {
    _settleFrom = _finger;
    _settleFromProgress = _progress;
    _settleTarget = target;
    _settleCurve = curve;
    _turnController
      ..duration = duration
      ..value = 0;
    unawaited(_turnController.forward());
  }

  /// 这次拖动"往哪拖算在翻"：RTL 往前翻是往右（+1），往回翻是往左。
  int get _dragSign {
    final forwardSign = widget.rightToLeft ? 1 : -1;
    return _forward ? forwardSign : -forwardSign;
  }

  void _startDrag(double dx, Offset position) {
    final forwardSign = widget.rightToLeft ? 1 : -1;
    final forward = dx * forwardSign > 0;
    final neighbour = forward ? widget.nextSpread : widget.previousSpread;
    if (neighbour == null) {
      _dragCandidate = false;
      return;
    }
    _begin(forward: forward);
    _phase = _TurnPhase.dragging;
    // 同一个事件里就把进度算出来：否则要等下一次 move 才动，手感会"慢半拍"。
    _updateDrag(position);
  }

  void _updateDrag(Offset position) {
    final along = (position.dx - _dragOrigin.dx) * _dragSign;
    final width = _viewport.width <= 0 ? 1.0 : _viewport.width;
    final motion = _motion;
    setState(() {
      _progress = (along / width).clamp(0.0, 1.0);
      if (motion != null) {
        _finger = motion.dragFinger(
          along: along,
          dy: position.dy - _dragOrigin.dy,
        );
      }
    });
  }

  void _cancelDrag() {
    _phase = _TurnPhase.idle;
    _progress = 0;
    _commit = false;
    _curl = false;
    setState(() {});
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
    return _SpreadFrame(
      order: order,
      sizes: sizes,
      layout: layout,
      content: Rect.fromLTWH(
        layout.content.left,
        layout.content.top,
        layout.content.width,
        layout.content.height,
      ),
    );
  }

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
          ),
        ),
    ],
  );

  Positioned _positioned(_SpreadFrame frame, Widget child) => Positioned(
    left: frame.content.left,
    top: frame.content.top,
    width: frame.content.width,
    height: frame.content.height,
    child: child,
  );

  /// 卷页层：被卷的那张纸（当前页或上一页）交给着色器，整块画布都画。
  Widget _curlLayer() {
    final sheet = _curlSheetFor(_forward);
    final motion = _motion;
    if (sheet == null || motion == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('reader-curl-layer'),
          painter: PageCurlPainter(
            sheet: sheet,
            sheetRect: _curlRect,
            frame: motion.frame(_finger, mirrored: _curlMirrored),
          ),
        ),
      ),
    );
  }

  /// 平移：把这一屏整体推出去，露出下面的相邻屏。
  Widget _slideLayer(_SpreadFrame frame) {
    final dx =
        (_mirrorFor(_forward) ? -1 : 1) * frame.content.width * _progress;
    return _positioned(
      frame,
      Transform.translate(offset: Offset(dx, 0), child: _spreadRow(frame)),
    );
  }

  /// 翻动中的图层，自下而上。
  ///
  /// - 往前卷：下一屏垫底，当前页被卷走；
  /// - 往回卷：当前屏垫底，上一页从书脊外卷回来盖上；
  /// - 平移：相邻屏垫底，当前屏被推走。
  List<Widget> _turningLayers(_SpreadFrame frame, _SpreadFrame? neighbour) {
    if (_curl && !_forward) {
      return <Widget>[_positioned(frame, _spreadRow(frame)), _curlLayer()];
    }
    return <Widget>[
      if (neighbour != null) _positioned(neighbour, _spreadRow(neighbour)),
      if (_curl) _curlLayer() else _slideLayer(frame),
    ];
  }

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
