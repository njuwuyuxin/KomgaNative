part of 'reader_paged_view.dart';

/// 指针单击区域与双击缩放判别（从 `_Zoom` 拆出，避免单类型膨胀，P2-5）。
///
/// 点击判定用自己的指针记账：`onTapUp` 与 `onScaleStart/Update` 在同一个
/// gesture arena 里会互相抢，实测 tap 会被 scale 吃掉导致翻页无响应。
mixin _TapDispatch on _PageTurn {
  /// 指针移动超过这个距离就不算点击（拖拽/缩放）。
  static const double _tapSlop = 12;

  int _activePointers = 0;
  Offset? _downAt;

  /// 中间区域的单击要等双击窗口过去才切 chrome：等不到第二下才算单击。
  Timer? _singleTapTimer;

  void _toggleZoomAt(Offset focal);

  @override
  void dispose() {
    _singleTapTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers++;
    _downAt = _activePointers == 1 ? event.localPosition : null;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointers > 0) _activePointers--;
    final down = _downAt;
    _downAt = null;
    if (down == null || _activePointers > 0) return;
    // 移动超过阈值视为拖拽/缩放，不当作点击。
    if ((event.localPosition - down).distance > _tapSlop) return;
    _handleTap(down, _viewport.width);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers = 0;
    _downAt = null;
  }

  /// 点击分派（RDR-07）：按用户选的点击区预设决定翻页/切 chrome。
  ///
  /// 翻页区**不等**双击窗口（为了双击把翻页拖慢 300ms 不可接受）；
  /// 中间区既要切 chrome、又要能双击缩放，所以单击必须等窗口过去——
  /// 除非用户关掉了双击缩放，那时中间区也立即生效。
  void _handleTap(Offset position, double width) {
    if (_phase != _TurnPhase.idle) return;
    final zone = resolveTapZone(
      preset: widget.tapZone,
      dx: position.dx,
      dy: position.dy,
      width: width,
      height: _viewport.height,
      rightToLeft: widget.rightToLeft,
      inverted: widget.invertTapZones,
    );
    if (zone == TapZoneAction.previous) {
      turn(-1);
      return;
    }
    if (zone == TapZoneAction.next) {
      turn(1);
      return;
    }
    if (!widget.doubleTapZoom) {
      widget.onToggleChrome();
      return;
    }
    final pending = _singleTapTimer;
    if (pending != null && pending.isActive) {
      pending.cancel();
      _singleTapTimer = null;
      _toggleZoomAt(position);
      return;
    }
    _singleTapTimer = Timer(kDoubleTapTimeout, () {
      _singleTapTimer = null;
      if (!mounted) return;
      widget.onToggleChrome();
    });
  }
}
