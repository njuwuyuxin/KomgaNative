import 'dart:async';

import 'package:komga_design_system/komga_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// 一组 sliver 的入场淡入（UI-P2-8）。
///
/// 为什么不是 `AnimatedSwitcher`：sliver 不能重叠，同一条 `CustomScrollView` 里
/// 新旧两态没法同时存在（那正是 `AnimatedSwitcher` 的做法）。所以这里只做
/// **入场淡入**：状态变了就淡入新的这一组，滚动位置不会被重置。
///
/// [phase] 是状态的稳定标识（`loading` / `error` / `empty` / `content`）：
/// 只有它变了才播一次，同态重建（追加下一页、滚动）不会闪。
class PhaseFade extends StatefulWidget {
  const PhaseFade({required this.phase, required this.slivers, super.key});

  final String phase;
  final List<Widget> slivers;

  @override
  State<PhaseFade> createState() => _PhaseFadeState();
}

class _PhaseFadeState extends State<PhaseFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = AppMotion.of(context);
    _controller.duration = motion.standard;
    if (_started) return;
    _started = true;
    if (motion.enabled) {
      unawaited(_controller.forward());
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(PhaseFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase == widget.phase) return;
    final motion = AppMotion.of(context);
    _controller.duration = motion.standard;
    _controller.value = 0;
    if (motion.enabled) unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverFadeTransition(
    opacity: _controller,
    sliver: SliverMainAxisGroup(slivers: widget.slivers),
  );
}
