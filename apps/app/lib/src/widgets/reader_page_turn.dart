part of 'reader_paged_view.dart';

/// 翻页动画：跟手拖动、点击自动翻页、松手补完，以及翻动中的图层。
mixin _PageTurn
    on
        ConsumerState<ReaderPagedView>,
        TickerProviderStateMixin<ReaderPagedView> {
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

  /// 本次翻动的卷页计划；null = 平移（开始时定下来，途中位图到了也不切换）。
  _CurlPlan? _plan;

  /// 卷页时被捏住的角所在位置（标准形纸面坐标，见 `curl_motion.dart`）。
  ({double x, double y}) _finger = (x: 0, y: 0);

  /// 补完动画的起点：松手时的手指位置与进度。
  ({double x, double y}) _settleFrom = (x: 0, y: 0);
  double _settleFromProgress = 0;
  double _settleTarget = 0;
  Curve _settleCurve = Curves.easeOutCubic;

  /// 卷页用的位图（单页：当前页、上一页；双页：两个方向各一张纸 + 纸背）。
  ///
  /// 没用 `RepaintBoundary.toImage()`：它在真机上取不到 layer（null check 崩），
  /// 本地 widget 测试却能跑，属于"测试绿、真机死"。页图字节本来就在仓库 LRU 里，
  /// 自己解成 `ui.Image` 更短也更可控。
  final CurlSheets _sheets = CurlSheets();

  // 由宿主 State 提供。
  double get _zoom;
  SizeD get _viewport;
  _SpreadFrame _frameFor(
    List<int> spread,
    SizeD viewport, {
    bool applyZoom = true,
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
  /// **放大状态下默认忽略**（UI-P1-6）：用户这时是在看放大的局部，误触翻页很恼人。
  /// 但开了"锁定缩放"（UI-P3-4）时允许翻页——锁定缩放的意义就是"放大着看、
  /// 翻页也不缩回去"，否则这个开关永远走不到翻页那一步。
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
    // 自动翻页：慢起（先掀起页脚）—快—慢收。
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
    // 只看 [requiredPages]：单页是"当前这一张纸"，双页是纸面 + 纸背。
    // 底层没就绪不再是退化条件（见 `_CurlPlan.requiredPages`）。
    final ready =
        plan != null &&
        PageCurlProgram.program != null &&
        plan.requiredPages.every((int p) => _sheets.imageFor(p) != null);
    _plan = ready ? plan : null;
    _finger = _plan?.motion.fingerAt(0) ?? (x: 0, y: 0);
  }

  void _onTurnTick() {
    if (!mounted || _phase != _TurnPhase.settling) return;
    final t = _settleCurve.transform(_turnController.value);
    setState(() {
      _progress =
          _settleFromProgress + (_settleTarget - _settleFromProgress) * t;
      final motion = _plan?.motion;
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
    final motion = _plan?.motion;
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
    _plan = null;
    setState(() {});
  }

  // ---- 图层 ----

  /// 卷页层：被卷的那张纸交给着色器，整块画布都画。
  Widget _curlLayer(_CurlPlan plan) {
    final sheet = _sheets.imageFor(plan.sheetPage);
    final backPage = plan.backPage;
    final back = backPage == null ? null : _sheets.imageFor(backPage);
    if (sheet == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('reader-curl-layer'),
          painter: PageCurlPainter(
            sheet: sheet,
            sheetRect: plan.sheetRect,
            back: back,
            backRect: plan.backRect,
            spineX: plan.spineX,
            frame: plan.motion.frame(_finger, mirrored: !widget.rightToLeft),
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

  /// 翻动中的图层，自下而上：垫底的页，再是卷页（或被推走的当前屏）。
  List<Widget> _turningLayers(_SpreadFrame frame, _SpreadFrame? neighbour) {
    final plan = _plan;
    if (plan != null) {
      return <Widget>[
        for (final (page, rect) in plan.under)
          Positioned.fromRect(
            rect: rect,
            child: ReaderPage(
              bookId: widget.bookId,
              pageIndex: page,
              palette: widget.palette,
              decodedImage: _sheets.imageFor(page),
            ),
          ),
        _curlLayer(plan),
      ];
    }
    return <Widget>[
      if (neighbour != null) _positioned(neighbour, _spreadRow(neighbour)),
      _slideLayer(frame),
    ];
  }
}
