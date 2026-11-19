import 'package:flutter/physics.dart';
import 'package:komga_design_system/src/motion.dart';
import 'package:material_ui/material_ui.dart';

/// 按下轻微缩小、松开弹簧回弹的包装（iOS 卡片的按压手感）。
///
/// 只负责"手感"：点击回调、语义仍由 [child] 自己处理（通常是 `InkWell` /
/// `GestureDetector`）。这里用 [Listener] 监听原始指针，不参与手势竞技场，
/// 所以不会抢走子组件的点击、长按或滚动。
///
/// 墨水屏 / 减少动态效果：不缩放（[AppMotion.enabled] 为 false 时直接透传）。
class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    this.pressedScale = defaultPressedScale,
    this.enabled = true,
    super.key,
  });

  /// 按下时的缩放比例。
  static const double defaultPressedScale = 0.97;

  final Widget child;
  final double pressedScale;

  /// 为 false 时完全透传（例如不可点击的卡片）。
  final bool enabled;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  /// 已经被移出树并 dispose 了。
  ///
  /// 指针事件是**异步**送达的：按住一张卡片时它可能已经因为重建/跳页被销毁，
  /// 松手（pointerUp）仍会派发到这个已经 dispose 的 State 上。
  /// 不挡住这一步 `AnimationController` 会直接断言崩溃。
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, AppMotion motion) {
    if (_disposed || !mounted) return;
    if (!motion.enabled) {
      _controller.value = 1;
      return;
    }
    _controller.animateWith(
      SpringSimulation(
        motion.snappy,
        _controller.value,
        target,
        _controller.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    if (!widget.enabled || !motion.enabled) return widget.child;
    return Listener(
      onPointerDown: (_) => _animateTo(widget.pressedScale, motion),
      onPointerUp: (_) => _animateTo(1, motion),
      onPointerCancel: (_) => _animateTo(1, motion),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) =>
            Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      ),
    );
  }
}
