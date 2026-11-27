part of 'reader_paged_view.dart';

/// 缩放与平移（UI-P1-6 / P2-5）。
///
/// 分工：
/// - `_PageTurn`：翻页动画（跟手、卷页、补完、换页）；
/// - `_TapDispatch`：指针点击区与双击缩放窗口判定；
/// - 本 mixin：双指缩放、溢出平移与弹簧缩放动画。
mixin _Zoom on _TapDispatch {
  /// 超过这个横向位移才开始跟手翻页（太小会误吃点击）。
  static const double _dragStartSlop = 14;

  /// 双击放大的倍数（Panels 一类阅读器都在 2–3 之间）。
  static const double _doubleTapZoom = 2.5;

  /// 弹簧积分的收敛容差：太大最后会"顿"一下，太小又要多跑几十帧。
  static const Tolerance _zoomTolerance = Tolerance(
    distance: 0.002,
    velocity: 0.02,
  );

  // 宿主（布局）在 build 时写、手势回调里读：
  int get _pageWidth;
  int get _pageHeight;
  ReadingMode get _engineMode;

  @override
  double _zoom = 1;
  Offset _pan = Offset.zero;
  Offset _startFocal = Offset.zero;
  Offset _startPan = Offset.zero;
  double _startZoom = 1;
  double _startScale = 1;
  Offset _startContent = Offset.zero;

  /// 最近一帧的"有效比例"与内容左上角：双击缩放要以它反推焦点。
  double _currentScale = 1;
  double _contentLeft = 0;
  double _contentTop = 0;

  /// 内容是否在某个方向上溢出视口（"填满屏幕"/"适应宽度"会让画面比视口大）。
  /// 溢出的方向单指拖动是**平移**，不是翻页。
  bool _overflowX = false;
  bool _overflowY = false;

  /// 平移的合法区间（`[min, 0]`）：夹紧后再存进 `_pan`，
  /// 否则拖过头再往回拖会出现"手指动了画面不动"的粘滞感。
  double _panMinX = 0;
  double _panMinY = 0;

  late final AnimationController _zoomAnimation =
      AnimationController.unbounded(vsync: this, value: 1)
        ..addListener(_onZoomTick)
        ..addStatusListener(_onZoomStatus);

  ({double zoom, Offset pan})? _zoomFrom;
  ({double zoom, Offset pan})? _zoomTarget;

  @override
  void dispose() {
    _zoomAnimation.dispose();
    super.dispose();
  }

  /// 换屏 / 换适配方式时把缩放与平移复位（并停掉正在跑的弹簧）。
  void _resetZoom() {
    _zoomAnimation.stop();
    _zoomFrom = null;
    _zoomTarget = null;
    _zoom = 1;
    _pan = Offset.zero;
  }

  // ---- 缩放 ----

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAnimation.stop();
    _startZoom = _zoom;
    _startPan = _pan;
    _startFocal = details.localFocalPoint;
    final layout = computePagedLayout(
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      viewport: _viewport,
      fit: widget.fit,
      mode: _engineMode,
      zoomFactor: _zoom,
      panX: _pan.dx,
      panY: _pan.dy,
    );
    _startScale = layout.scale;
    _startContent = Offset(layout.content.left, layout.content.top);
    _gestureZoom = details.pointerCount > 1;
    _dragOrigin = details.localFocalPoint;
    // 画面横向溢出时，横向拖动是在"平移看被裁掉的部分"，不能同时当翻页。
    _dragCandidate = _canAnimate && !_overflowX;
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
    if (_zoom > 1.0) {
      _applyZoom(details);
      return;
    }
    // 没放大但画面比视口大（填满屏幕 / 适应宽度）：单指平移。
    if (_overflowX || _overflowY) _applyPan(details);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _dragCandidate = false;
    _gestureZoom = false;
    if (_phase != _TurnPhase.dragging) return;
    _endDrag(details);
  }

  void _applyPan(ScaleUpdateDetails details) {
    final dx = _startPan.dx + (details.localFocalPoint.dx - _startFocal.dx);
    final dy = _startPan.dy + (details.localFocalPoint.dy - _startFocal.dy);
    setState(() {
      _pan = Offset(
        _overflowX ? dx.clamp(_panMinX, 0.0).toDouble() : 0,
        _overflowY ? dy.clamp(_panMinY, 0.0).toDouble() : 0,
      );
    });
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

  /// 双击：没放大就放大到 [_doubleTapZoom]（以双击点为中心），已放大就还原。
  void _toggleZoomAt(Offset focal) {
    final motion = AppMotion.of(context);
    if (_zoom > 1.0) {
      _animateZoomTo(zoom: 1, pan: Offset.zero, motion: motion);
      return;
    }
    final nextScale = computePagedLayout(
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      viewport: _viewport,
      fit: widget.fit,
      mode: _engineMode,
      zoomFactor: _doubleTapZoom,
    ).scale;
    final origin = zoomAboutFocal(
      contentLeft: _contentLeft,
      contentTop: _contentTop,
      scale: _currentScale,
      nextScale: nextScale,
      focalX: focal.dx,
      focalY: focal.dy,
    );
    _animateZoomTo(
      zoom: _doubleTapZoom,
      pan: Offset(origin.left, origin.top),
      motion: motion,
    );
  }

  /// 用 `gentle` 弹簧把 (缩放, 平移) 从当前值送到目标值。
  ///
  /// 弹簧跑的是归一化的 0→1 参数，再对 (zoom, pan) 线性插值：
  /// 两者本来就是同一条直线上的起终点，插值不会偏离"焦点不动"的轨迹。
  void _animateZoomTo({
    required double zoom,
    required Offset pan,
    required AppMotion motion,
  }) {
    if (!motion.enabled) {
      // 墨水屏 / 减少动态效果：直接到位。
      setState(() {
        _zoom = zoom;
        _pan = pan;
      });
      return;
    }
    _zoomFrom = (zoom: _zoom, pan: _pan);
    _zoomTarget = (zoom: zoom, pan: pan);
    _zoomAnimation
      ..stop()
      ..value = 0;
    unawaited(
      _zoomAnimation.animateWith(
        SpringSimulation(motion.gentle, 0, 1, 0, tolerance: _zoomTolerance),
      ),
    );
  }

  void _onZoomTick() {
    final from = _zoomFrom;
    final to = _zoomTarget;
    if (from == null || to == null) return;
    final t = _zoomAnimation.value.clamp(0.0, 1.0);
    setState(() {
      _zoom = from.zoom + (to.zoom - from.zoom) * t;
      _pan = Offset.lerp(from.pan, to.pan, t) ?? to.pan;
    });
  }

  /// 弹簧收敛后**精确落位**。
  ///
  /// 容差内停下的值可能差千分之几：放大时无所谓，但"回到 1"时必须真的是 1，
  /// 否则 `_zoom <= 1` 这个判定会一直为假，翻页从此失效（踩过一次）。
  void _onZoomStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final to = _zoomTarget;
    _zoomFrom = null;
    _zoomTarget = null;
    if (to == null) return;
    setState(() {
      _zoom = to.zoom;
      _pan = to.pan;
    });
  }
}
