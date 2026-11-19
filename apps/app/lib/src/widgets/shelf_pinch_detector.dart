import 'package:material_ui/material_ui.dart';

/// 双指捏合调整书架封面大小（UI-P2-7）。
///
/// 用 [Listener] 而不是 `GestureDetector`：后者会和 `CustomScrollView` 抢手势，
/// 单指滚动会先被它吃掉；`Listener` 只看原始指针，不参与竞技场，滚动照常。
/// 只有**两根手指**的距离变化超过阈值才回调，避免双指滚动时误触。
class ShelfPinchDetector extends StatefulWidget {
  const ShelfPinchDetector({
    required this.child,
    required this.onPinch,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// +1 = 放大一档，-1 = 缩小一档。
  final ValueChanged<int> onPinch;

  final bool enabled;

  @override
  State<ShelfPinchDetector> createState() => _ShelfPinchDetectorState();
}

class _ShelfPinchDetectorState extends State<ShelfPinchDetector> {
  /// 当前按下的指针位置；指针 id → 全局坐标。
  final Map<int, Offset> _points = <int, Offset>{};

  /// 本次双指手势的起始距离；一次手势只换一档。
  double? _startDistance;
  bool _stepped = false;

  double get _distance {
    final points = _points.values.toList(growable: false);
    if (points.length < 2) return 0;
    return (points[0] - points[1]).distance;
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    _points[event.pointer] = event.position;
    if (_points.length == 2) {
      _startDistance = _distance;
      _stepped = false;
    }
  }

  void _move(PointerMoveEvent event) {
    if (!widget.enabled || !_points.containsKey(event.pointer)) return;
    _points[event.pointer] = event.position;
    final start = _startDistance;
    if (_points.length != 2 || start == null || start <= 0 || _stepped) return;

    final ratio = _distance / start;
    if (ratio > 1.18) {
      _stepped = true;
      widget.onPinch(1);
    } else if (ratio < 0.85) {
      _stepped = true;
      widget.onPinch(-1);
    }
  }

  void _up(PointerEvent event) {
    _points.remove(event.pointer);
    if (_points.length < 2) {
      _startDistance = null;
      _stepped = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: widget.child,
    );
  }
}
