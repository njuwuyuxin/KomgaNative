part of 'reader_paged_view.dart';

/// 翻页动画：跟手拖动、点击自动翻页、松手补完，以及翻动中的图层。
mixin _PageTurn
    on
        ConsumerState<ReaderPagedView>,
        TickerProviderStateMixin<ReaderPagedView> {
  late final AnimationController _turnController;
  late final _CurlFaceFade _faceFade;
  _TurnPhase _phase = _TurnPhase.idle;
  bool _forward = true;
  bool _commit = false;
  bool _gestureZoom = false;
  bool _dragCandidate = false;
  Offset _dragOrigin = Offset.zero;

  /// 翻页进度（0..1）：松手判定、平移效果、测试都看它。
  double _progress = 0;

  /// 本次翻动的卷页计划；null = 平移（开始时定下来，途中位图到了也不切换模式）。
  _CurlPlan? _plan;

  double get _sheetMix => _faceFade.sheetMix;
  double get _backMix => _faceFade.backMix;

  /// 卷页时被捏住的角所在位置（标准形纸面坐标，见 `curl_motion.dart`）。
  ({double x, double y}) _finger = (x: 0, y: 0);

  /// 补完动画的起点：松手时的手指位置与进度。
  ({double x, double y}) _settleFrom = (x: 0, y: 0);
  double _settleFromProgress = 0;
  double _settleTarget = 0;
  Curve _settleCurve = Curves.easeOutCubic;

  /// 卷页用的位图缓存（与 `ImageCache` 共享底层纹理，保留最近访问的页面供回翻复用）。
  late final CurlSheets _sheets = CurlSheets(onImageReady: _onSheetDecoded);
  bool _sheetsScheduled = false;

  // 由宿主 State 提供。
  double get _zoom;
  SizeD get _viewport;
  _SpreadFrame _frameFor(
    List<int> spread,
    SizeD viewport, {
    bool applyZoom = true,
    PageHalf half = PageHalf.full,
  });
  Widget _spreadRow(_SpreadFrame frame);
  Positioned _positioned(_SpreadFrame frame, Widget child);

  @override
  void initState() {
    super.initState();
    _turnController = AnimationController(
      vsync: this,
      duration: widget.style.duration,
    )..addListener(_onTurnTick);
    _turnController.addStatusListener(_onTurnStatus);
    _faceFade = _CurlFaceFade(
      vsync: this,
      onTick: () {
        if (mounted && _phase != _TurnPhase.idle) setState(() {});
      },
    );
    unawaited(PageCurlProgram.ensureLoaded());
    _scheduleSheets();
  }

  @override
  void dispose() {
    _faceFade.dispose();
    _turnController.dispose();
    _sheets.dispose();
    super.dispose();
  }

  /// 由外部（底栏箭头 / 音量键 / 点击）触发的翻页：和拖动走同一套动画。
  void turn(int delta) {
    if (_phase != _TurnPhase.idle) return;
    if (_zoom > 1.0 && !widget.lockZoom) return;
    final neighbour = delta > 0 ? widget.nextSpread : widget.previousSpread;
    if (neighbour == null || !_canAnimate) {
      widget.onTurn(delta);
      return;
    }
    _begin(forward: delta > 0);
    _commit = true;
    _phase = _TurnPhase.settling;
    setState(() {});
    _startSettle(1, widget.style.duration, Curves.easeInOutCubic);
  }

  @visibleForTesting
  double get debugProgress => _progress;

  /// 本次翻动是否在用卷页（否则是平移）。
  @visibleForTesting
  bool get debugCurling => _plan != null;

  /// 本次卷页是否铰接在书脊上（双页）。
  @visibleForTesting
  bool get debugHinged => _plan?.motion.hinged ?? false;

  void _begin({required bool forward}) {
    _forward = forward;
    _progress = 0;
    final plan = _planFor(forward);
    if (plan != null) {
      // 起手瞬间同步把已在 `ImageCache`（屏幕已显示或已预热）的页图借入 `_sheets`。
      for (final page in plan.pages) {
        _imageOrAdoptSync(page);
      }
    }
    final ready =
        plan != null &&
        PageCurlProgram.program != null &&
        plan.requiredPages.every((int p) => _sheets.imageFor(p) != null);
    _plan = ready ? plan : null;
    _finger = _plan?.motion.fingerAt(0) ?? (x: 0, y: 0);

    final active = _plan;
    if (active != null) {
      final sheetReady = _sheets.imageFor(active.sheetPage) != null;
      final backPage = active.backPage;
      final backReady = backPage == null || _sheets.imageFor(backPage) != null;
      _faceFade.begin(
        sheetReady: sheetReady,
        hasBack: backPage != null,
        backReady: backReady,
      );
      if (!sheetReady || !backReady) _scheduleSheets();
    } else {
      _faceFade.resetOpaque();
    }
  }

  void _onSheetDecoded(int page) {
    if (!mounted || _phase == _TurnPhase.idle) return;
    final plan = _plan;
    if (plan == null || !plan.pages.contains(page)) return;
    _checkLateFaces(plan);
    setState(() {});
  }

  void _checkLateFaces(_CurlPlan plan) {
    _faceFade.checkLate(
      hasSheetImage: () => _imageOrAdoptSync(plan.sheetPage) != null,
      hasBackPage: plan.backPage != null,
      hasBackImage: () =>
          plan.backPage != null && _imageOrAdoptSync(plan.backPage!) != null,
    );
  }

  void _onTurnTick() {
    if (!mounted || _phase != _TurnPhase.settling) return;
    final plan = _plan;
    if (plan != null) _checkLateFaces(plan);
    final t = _settleCurve.transform(_turnController.value);
    setState(() {
      _progress =
          _settleFromProgress + (_settleTarget - _settleFromProgress) * t;
      final motion = plan?.motion;
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
    _plan = null;
    _progress = 0;
    _faceFade.stop();
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

  bool _mirrorFor(bool forward) =>
      forward ? !widget.rightToLeft : widget.rightToLeft;

  // ---- 跟手 ----

  void _endDrag(ScaleEndDetails details) {
    final decision = settlePageTurn(
      progress: _progress,
      velocityX: details.velocity.pixelsPerSecond.dx,
      base: widget.style.duration,
      forwardSign: _dragSign,
    );
    _commit = decision.commit;
    _phase = _TurnPhase.settling;
    _startSettle(
      decision.commit ? 1 : 0,
      decision.duration,
      Curves.easeOutCubic,
    );
  }

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
    _updateDrag(position);
  }

  void _updateDrag(Offset position) {
    final along = (position.dx - _dragOrigin.dx) * _dragSign;
    final width = _viewport.width <= 0 ? 1.0 : _viewport.width;
    final plan = _plan;
    if (plan != null) _checkLateFaces(plan);
    setState(() {
      _progress = (along / width).clamp(0.0, 1.0);
      final motion = plan?.motion;
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
    _plan = null;
    _faceFade.stop();
    setState(() {});
    _scheduleSheets();
  }
}
