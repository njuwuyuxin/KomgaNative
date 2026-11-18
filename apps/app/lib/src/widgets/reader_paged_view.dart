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
/// 翻页动画也在这里：横向拖动时把当前屏截成一张快照（`toImage`），
/// 上层用着色器把快照卷起来（`page_curl.dart`），下层露出相邻那一屏。
/// 快照只在空闲时拍，所以开始拖的那一刻就有图可用。
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
  bool _mirrored = false;
  double _progress = 0;
  bool _commit = false;
  bool _gestureZoom = false;
  bool _dragCandidate = false;
  Offset _dragOrigin = Offset.zero;

  /// 卷页用的"这张纸"：当前页解码后的位图。
  ///
  /// 没用 `RepaintBoundary.toImage()`：它在真机上取不到 layer（null check 崩），
  /// 本地 widget 测试却能跑，属于"测试绿、真机死"。页图字节本来就在仓库 LRU 里，
  /// 自己解成 `ui.Image` 更短也更可控。
  ui.Image? _sheet;
  Rect _sheetRect = Rect.zero;

  /// 已经不再使用、但可能还被上一帧的 raster 线程引用着的贴图。
  ///
  /// 立刻 `dispose()` 有时会闪一帧空白；统一等下一帧结束再释放。
  final List<ui.Image> _retired = <ui.Image>[];

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

  @override
  void initState() {
    super.initState();
    _turnController = AnimationController(
      vsync: this,
      duration: widget.style.duration,
    )..addListener(_onTurnTick);
    _turnController.addStatusListener(_onTurnStatus);
    unawaited(PageCurlProgram.ensureLoaded());
    _scheduleSheet();
  }

  @override
  void dispose() {
    _turnController.dispose();
    _sheet?.dispose();
    _flushRetired();
    super.dispose();
  }

  /// 由外部（底栏箭头 / 音量键）触发的翻页：和点击走同一套动画。
  ///
  /// 没有快照/不允许动画时直接翻页——宁可瞬切，也不要假装有动画。
  void turn(int delta) {
    if (_phase != _TurnPhase.idle) return;
    final neighbour = delta > 0 ? widget.nextSpread : widget.previousSpread;
    if (neighbour == null || !_canAnimate) {
      widget.onTurn(delta);
      return;
    }
    _forward = delta > 0;
    _mirrored = _mirrorFor(_forward);
    _commit = true;
    _progress = 0;
    _phase = _TurnPhase.settling;
    setState(() {});
    _startSettle(1, widget.style.duration);
  }

  @visibleForTesting
  double get debugProgress => _progress;

  void _onTurnTick() {
    if (!mounted) return;
    setState(() => _progress = _turnController.value);
  }

  void _onTurnStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed &&
        status != AnimationStatus.dismissed) {
      return;
    }
    if (_phase != _TurnPhase.settling) return;
    final commit = _commit;
    _phase = _TurnPhase.idle;
    _commit = false;
    _progress = 0;
    // 必须归零：否则下一次 `animateTo(1)` 因为"目标等于当前值"直接完成、
    // 状态没变化也就不会回调 status listener，翻页会卡死在 settling。
    _turnController.reset();
    setState(() {});
    if (commit) widget.onTurn(_forward ? 1 : -1);
    _scheduleSheet();
  }

  bool get _canAnimate =>
      widget.style.animates &&
      _phase == _TurnPhase.idle &&
      _zoom <= 1.0 &&
      _viewport.width > 0;

  /// 书脊在右边（RTL）时"往前翻"从左边掀起；镜像方向用于往后翻。
  bool _mirrorFor(bool forward) =>
      forward ? !widget.rightToLeft : widget.rightToLeft;

  PageTurnEffect get _effect {
    if (widget.style.effect != PageTurnEffect.curl) return widget.style.effect;
    // 往后翻需要"上一屏的快照"，我们只有当前屏的；退化成平移。
    if (!_forward || _sheet == null || PageCurlProgram.program == null) {
      return PageTurnEffect.slide;
    }
    return PageTurnEffect.curl;
  }

  /// 空闲时把当前页解码成位图，供下一次卷页使用。
  ///
  /// 单页模式才需要（双页/往后翻都走平移，不需要位图）；解码失败就不做卷页，
  /// 自动退化成平移，不打断阅读。
  void _scheduleSheet() {
    if (widget.style.effect != PageTurnEffect.curl) return;
    if (widget.spread.length != 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _phase != _TurnPhase.idle) return;
      unawaited(_decodeSheet(widget.spread.first));
    });
  }

  Future<void> _decodeSheet(int pageIndex) async {
    final repository = ref.read(readerRepositoryProvider);
    final page = pageIndex + 1;
    Uint8List? bytes = repository.cachedPageImage(widget.bookId, page);
    try {
      bytes ??= await repository.pageImage(widget.bookId, page);
    } on ShelfFailure {
      return;
    }
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted || _phase != _TurnPhase.idle) {
      frame.image.dispose();
      return;
    }
    final old = _sheet;
    _sheet = frame.image;
    _retire(old);
  }

  void _dropSheet() {
    final old = _sheet;
    _sheet = null;
    _retire(old);
  }

  @override
  void didUpdateWidget(ReaderPagedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了一屏就复位：上一屏的缩放/平移套到新页上会看到莫名其妙的位置。
    if (!_sameSpread(oldWidget.spread, widget.spread)) {
      _zoom = 1;
      _pan = Offset.zero;
      _dropSheet();
      _scheduleSheet();
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
    final sign = _forward
        ? (widget.rightToLeft ? 1 : -1)
        : (widget.rightToLeft ? -1 : 1);
    final decision = settlePageTurn(
      progress: _progress,
      velocityX: details.velocity.pixelsPerSecond.dx,
      base: widget.style.duration,
      forwardSign: sign,
    );
    _commit = decision.commit;
    _phase = _TurnPhase.settling;
    _startSettle(decision.commit ? 1 : 0, decision.duration);
  }

  /// 从**当前已翻进度**补完剩下的动画。
  ///
  /// 直接 `animateTo(target)` 的话起点是 controller 的旧值（0），表现就是
  /// "已经翻了 70%，一松手跳回 0 再重播"。这里先把 controller 对齐到 [_progress]，
  /// 再按剩余距离反算时长——`animateTo` 自己会按剩余比例压缩时长，
  /// 所以传入的时长要除回去，保证总时长仍然等于 [duration]。
  void _startSettle(double target, Duration duration) {
    final remaining = (target - _progress).abs().clamp(0.001, 1.0);
    _turnController.value = _progress;
    unawaited(
      _turnController.animateTo(
        target,
        duration: Duration(
          milliseconds: (duration.inMilliseconds / remaining).round(),
        ),
        // easeOutCubic：尾巴更长、更软，翻页结束时不会"戛然而止"。
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _startDrag(double dx, Offset position) {
    final forwardSign = widget.rightToLeft ? 1 : -1;
    final forward = dx * forwardSign > 0;
    final neighbour = forward ? widget.nextSpread : widget.previousSpread;
    if (neighbour == null) {
      _dragCandidate = false;
      return;
    }
    _forward = forward;
    _mirrored = _mirrorFor(forward);
    _progress = 0;
    _phase = _TurnPhase.dragging;
    // 同一个事件里就把进度算出来：否则要等下一次 move 才动，手感会"慢半拍"。
    _updateDrag(position);
  }

  void _updateDrag(Offset position) {
    final distance = (position.dx - _dragOrigin.dx).abs();
    final width = _viewport.width <= 0 ? 1.0 : _viewport.width;
    setState(() => _progress = (distance / width).clamp(0.0, 1.0));
  }

  void _cancelDrag() {
    _phase = _TurnPhase.idle;
    _progress = 0;
    _commit = false;
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

  /// 翻页过程中的上层：有当前页位图就卷页，否则把这一屏整体推出去（平移）。
  Widget _turningLayer(_SpreadFrame frame) {
    final sheet = _sheet;
    if (_effect == PageTurnEffect.curl && sheet != null) {
      return Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: PageCurlPainter(
              sheet: sheet,
              sheetRect: _sheetRect,
              geometry: curlGeometry(
                progress: _progress,
                width: _sheetRect.width,
                height: _sheetRect.height,
                mirrored: _mirrored,
              ),
            ),
          ),
        ),
      );
    }
    final dx = (_mirrored ? -1 : 1) * frame.content.width * _progress;
    return _positioned(
      frame,
      Transform.translate(offset: Offset(dx, 0), child: _spreadRow(frame)),
    );
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
        _sheetRect = frame.content;
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
              children: <Widget>[
                if (neighbourFrame != null)
                  _positioned(neighbourFrame, _spreadRow(neighbourFrame)),
                if (turning)
                  _turningLayer(frame)
                else
                  _positioned(frame, _spreadRow(frame)),
              ],
            ),
          ),
        );
      },
    );
  }
}
