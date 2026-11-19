import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 从屏幕边缘往中间拖，返回上一页（UI-P2-3）。
///
/// 为什么不是真正的 Cupertino 交互式返回：Flutter 3.47 之后
/// `package:flutter/cupertino.dart` 被标记废弃（要求换 `cupertino_ui` 新依赖），
/// 而返回手势在 Cupertino 的 `PageRoute` 里、不在转场 builder 里。这里用一条
/// **只在边缘 24px 生效**的横向手势条实现"右滑返回"：命中阈值/速度就 `maybePop`，
/// 页面本身仍走主题里的侧滑转场。手指跟手拖动的那一层动画没有做——文档里明说。
///
/// 只在非墨水屏、"减少动态效果"关闭、且当前路由可以 pop 时生效；
/// 墨水屏用返回键/系统返回，不做手势。
class EdgeSwipeBack extends StatefulWidget {
  const EdgeSwipeBack({
    required this.child,
    this.edgeWidth = 24,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// 手势条的宽度（逻辑像素）。太宽会抢页面本身的横向拖动。
  final double edgeWidth;

  /// 显式关闭（测试/特殊页面用）；默认仍会按墨水屏与"减少动态效果"退化。
  final bool enabled;

  @override
  State<EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<EdgeSwipeBack> {
  /// 本次拖动累计的"返回方向"位移。
  double _drag = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final route = ModalRoute.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.enabled ||
        route?.canPop != true ||
        AppTheme.isEink(theme) ||
        reduceMotion) {
      return widget.child;
    }

    // RTL 下"返回"是从右边缘往左拖。
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Stack(
      children: <Widget>[
        widget.child,
        Positioned(
          left: rtl ? null : 0,
          right: rtl ? 0 : null,
          top: 0,
          bottom: 0,
          width: widget.edgeWidth,
          child: GestureDetector(
            key: const Key('edge-swipe-back'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (DragStartDetails details) => _drag = 0,
            onHorizontalDragUpdate: (DragUpdateDetails details) {
              _drag += rtl ? -details.delta.dx : details.delta.dx;
            },
            onHorizontalDragEnd: (DragEndDetails details) {
              final velocity = details.primaryVelocity ?? 0;
              final forward = rtl ? -velocity : velocity;
              // 距离够远或甩得够快都算返回；慢速小幅拖动不误触。
              if (_drag > 64 || forward > 700) {
                Navigator.of(context).maybePop();
              }
              _drag = 0;
            },
          ),
        ),
      ],
    );
  }
}
