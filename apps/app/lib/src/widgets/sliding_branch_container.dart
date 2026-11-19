import 'package:flutter/physics.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 主页面分支容器：切换 dock tab 时让旧页和新页水平滑动。
///
/// 替代 go_router 默认的 `IndexedStack`（`StatefulShellRoute.indexedStack`）：
/// - **所有分支始终挂在树上**，用 [Offstage] 隐藏而不是销毁，分支内的滚动位置、
///   返回栈与页面状态都保留；
/// - 切换时只显示旧页与新页：旧页向切换方向滑出，新页从另一侧滑入，中间不
///   播放路过的分支（远距离切 tab 不会闪过 Library / Collections）；
/// - **不接管手势**：主页面里还有收藏页自己的横向 `TabBarView`，这里再放一层
///   可拖动的 `PageView` 会和它抢手势。滑动只由 tab 点击驱动。
///
/// 动画用 [AppMotion.gentle] 弹簧（页面级手感，比 [AppMotion.snappy] 更稳）；
/// 墨水屏 / 系统"减少动态效果"直接切页，不跑弹簧（由 [AppMotion] 退化）。
class SlidingBranchContainer extends StatefulWidget {
  const SlidingBranchContainer({
    required this.currentIndex,
    required this.children,
    super.key,
  });

  /// 当前分支下标（与 `StatefulNavigationShell.currentIndex` 一致）。
  final int currentIndex;

  /// 每个分支的 Navigator；顺序与 `StatefulShellRoute.branches` 一致。
  final List<Widget> children;

  @override
  State<SlidingBranchContainer> createState() => _SlidingBranchContainerState();
}

class _SlidingBranchContainerState extends State<SlidingBranchContainer>
    with SingleTickerProviderStateMixin {
  /// 0 → 1：0 = 旧页居中，1 = 新页居中。unbounded 让弹簧可以带一点点过冲。
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  late int _fromIndex = widget.currentIndex;
  late int _toIndex = widget.currentIndex;

  /// 正在跑向哪一端：1 = 新页，0 = 旧页（用户又点回去了）。
  double _target = 1;

  @override
  void didUpdateWidget(covariant SlidingBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex == oldWidget.currentIndex) return;

    final motion = AppMotion.of(context);
    if (!motion.enabled) {
      _jumpToCurrent();
      return;
    }

    final next = widget.currentIndex;
    if (_controller.isAnimating) {
      if (next == _toIndex) {
        // 已经朝新页走了；如果正在回退，再把它推回去。
        if (_target != 1) _animateTo(1, motion);
        return;
      }
      if (next == _fromIndex) {
        // 用户在滑动中途点了旧页：原地反向。
        if (_target != 0) _animateTo(0, motion);
        return;
      }
      // 第三次点击：以当前更靠近屏幕中间的一页为起点，重新滑向新目标。
      final active = _controller.value >= 0.5 ? _toIndex : _fromIndex;
      _fromIndex = active;
      _toIndex = next;
      _target = 1;
      _controller.value = 0;
      _animateTo(1, motion);
      return;
    }

    _fromIndex = oldWidget.currentIndex;
    _toIndex = next;
    _target = 1;
    _controller.value = 0;
    _animateTo(1, motion);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 动画中途切到墨水屏 / 打开"减少动态效果"：不要继续跑完弹簧。
    if (!AppMotion.of(context).enabled && _controller.isAnimating) {
      _jumpToCurrent();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, AppMotion motion) {
    _target = target;
    _controller.animateWith(
      SpringSimulation(
        motion.gentle,
        _controller.value,
        target,
        _controller.velocity,
      ),
    );
  }

  void _jumpToCurrent() {
    _fromIndex = _toIndex = widget.currentIndex;
    _target = 1;
    _controller.value = 1;
  }

  /// 某一页在滑动中的横向偏移，单位是"页宽"（[FractionalTranslation] 的语义）。
  double _offsetFor(
    int index,
    bool animating,
    double progress,
    double direction,
    double axisSign,
  ) {
    if (!animating) return 0;
    if (index == _fromIndex) return -direction * progress * axisSign;
    if (index == _toIndex) return direction * (1 - progress) * axisSign;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // 注册动画偏好依赖：墨水屏 / 减少动态效果切换时能收到重建。
    AppMotion.of(context);
    final axisSign = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;

    // ClipRect 必须有：FractionalTranslation 不会把"画出边界"报告给 Stack，
    // 不裁的话滑出的一半会盖到 dock 和状态栏上。
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final animating = _controller.isAnimating && _fromIndex != _toIndex;
          final progress = animating ? _controller.value : 1.0;
          final direction = _toIndex > _fromIndex ? 1.0 : -1.0;

          bool isVisible(int index) => animating
              ? index == _fromIndex || index == _toIndex
              : index == widget.currentIndex;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              for (var i = 0; i < widget.children.length; i++)
                Positioned.fill(
                  child: Offstage(
                    offstage: !isVisible(i),
                    child: TickerMode(
                      enabled: isVisible(i),
                      child: FractionalTranslation(
                        translation: Offset(
                          _offsetFor(
                            i,
                            animating,
                            progress,
                            direction,
                            axisSign,
                          ),
                          0,
                        ),
                        child: widget.children[i],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
