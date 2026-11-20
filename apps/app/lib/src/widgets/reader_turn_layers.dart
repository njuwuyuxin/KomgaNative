part of 'reader_paged_view.dart';

/// 翻页过程中的视图图层构建：垫底页（含宽页半幅裁切）、着色器卷页层与回退平移层。
extension _TurnLayers on _PageTurn {
  /// 卷页层：被卷的那张纸交给着色器，整块画布都画。
  Widget _curlLayer(_CurlPlan plan) {
    final sheet = _sheets.imageFor(plan.sheetPage);
    final backPage = plan.backPage;
    final back = backPage == null ? null : _sheets.imageFor(backPage);
    if (sheet == null && back == null) return const SizedBox.shrink();
    final hasColdHingedFace =
        plan.motion.hinged &&
        (sheet == null ||
            _sheetMix < 1 ||
            (backPage != null && (back == null || _backMix < 1)));
    // 深色背景下若相邻屏仍在网络加载中，纸背/冷面使用贴合阅读区底色的哑光深灰纸面，
    // 避免整块纯白刺眼并在落地或渐显时产生突兀闪变。
    final paperColor = hasColdHingedFace && !widget.palette.isLight
        ? Color.lerp(widget.palette.background, const Color(0xFFFFFFFF), 0.12)
        : null;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('reader-curl-layer'),
          painter: PageCurlPainter(
            sheet: sheet,
            sheetRect: plan.sheetRect,
            sheetUvRect: plan.sheetUvRect,
            back: back,
            backRect: plan.backRect,
            backUvRect: plan.backUvRect,
            spineX: plan.spineX,
            hinged: plan.motion.hinged,
            sheetOpacity: _sheetMix,
            backOpacity: _backMix,
            paperColor: paperColor,
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

  /// 垫在卷页下方的单页或宽页半幅（宽页跨页图按 [slot.clip] 精确裁出左/右半页）。
  Widget _underSlotWidget(_HalfSheet slot) {
    final page = ReaderPage(
      bookId: widget.bookId,
      pageIndex: slot.page,
      palette: widget.palette,
      decodedImage: _sheets.imageFor(slot.page),
      trimBorders: widget.trimBorders,
    );
    if (slot.clip == slot.image) {
      return Positioned.fromRect(rect: slot.clip, child: page);
    }
    return Positioned.fromRect(
      rect: slot.clip,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          Positioned(
            left: slot.image.left - slot.clip.left,
            top: slot.image.top - slot.clip.top,
            width: slot.image.width,
            height: slot.image.height,
            child: page,
          ),
        ],
      ),
    );
  }

  /// 翻动中的图层，自下而上：垫底的页，再是卷页（或被推走的当前屏）。
  List<Widget> _turningLayers(_SpreadFrame frame, _SpreadFrame? neighbour) {
    final plan = _plan;
    if (plan != null) {
      return <Widget>[
        for (final slot in plan.under) _underSlotWidget(slot),
        _curlLayer(plan),
      ];
    }
    return <Widget>[
      if (neighbour != null) _positioned(neighbour, _spreadRow(neighbour)),
      _slideLayer(frame),
    ];
  }
}
