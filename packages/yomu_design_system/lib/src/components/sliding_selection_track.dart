import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:yomu_design_system/src/components/sliding_selection_math.dart';
import 'package:yomu_design_system/src/motion.dart';
import 'package:yomu_design_system/src/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// 槽位内容的构建器：`selection` 是该项当前的选中进度（0 → 1）。
///
/// 切换选项时它跟着滑块一起变化，文字 / 图标颜色按它插值即可与胶囊同步；
/// 稳态下选中项是 1、其余是 0。
typedef SlidingSelectionItemBuilder = Widget Function(
  BuildContext context,
  int index,
  double selection,
);

/// 一条会滑动的选中胶囊 + 逐项选中进度。
///
/// 顶部标题栏的分段控件（收藏集 / 阅读列表、主题 / 语言、库筛选）与底部
/// 导航条共用：选中态不再是每一项各自淡入淡出，而是**同一块**胶囊从旧槽位
/// 弹到新槽位。位置用 [AppMotion.snappy] 弹簧（与 `PressableScale` 同一手感），
/// 文字 / 图标颜色按同一进度过渡——这正是"按下加深"从瞬变变成有方向感的
/// 关键；只淡入淡出会像两个按钮各自亮了一下。
///
/// 槽位几何不在调用方硬编码：布局完成后量一次每个槽位的实际矩形，
/// 因此等分（分段控件）与按内容定宽（库筛选、导航条标签）走同一条路径。
/// 动画中途再点别的选项时，从胶囊当前所在位置继续弹，不会跳回旧槽位。
///
/// 墨水屏 / 系统"减少动态效果"：不跑弹簧、直接到终值（由 [AppMotion] 退化）。
class SlidingSelectionTrack extends StatefulWidget {
  const SlidingSelectionTrack({
    required this.itemCount,
    required this.selectedIndex,
    required this.itemBuilder,
    required this.pillColor,
    required this.pillShape,
    this.position,
    this.padding = EdgeInsets.zero,
    this.pillInset = EdgeInsets.zero,
    this.gap = AppSpacing.xs,
    this.scrollable = false,
    super.key,
  }) : assert(itemCount > 0, '至少一个槽位');

  /// 槽位数量。
  final int itemCount;

  /// 当前选中的槽位；null = 没有选中项（导航条停在搜索页时），胶囊淡出。
  final int? selectedIndex;

  /// 外部连续选中位置（例如 `TabController.animation`，取值 `[0, itemCount - 1]`）。
  /// 传值时胶囊位置与逐项权重直接随它插值，不另起内部弹簧，与页面滑动保持同步。
  final ValueListenable<double>? position;

  /// 每个槽位的内容；`selection` 用于颜色插值，见 [SlidingSelectionItemBuilder]。
  final SlidingSelectionItemBuilder itemBuilder;

  /// 选中胶囊的底色与形状（由调用方按主题 / 墨水屏解析）。
  final Color pillColor;
  final ShapeBorder pillShape;

  /// 整条内容四周的留白；槽位坐标都相对这块留白的内侧。
  final EdgeInsets padding;

  /// 选中胶囊相对槽位的额外内缩（导航条的"四边等宽"就是它）。
  final EdgeInsets pillInset;

  /// 槽位之间的横向间距。
  final double gap;

  /// true = 按内容定宽并允许横向滚动；false = 等分整条宽度。
  final bool scrollable;

  @override
  State<SlidingSelectionTrack> createState() => _SlidingSelectionTrackState();
}

class _SlidingSelectionTrackState extends State<SlidingSelectionTrack>
    with SingleTickerProviderStateMixin {
  /// 0 → 1 的弹簧进度：0 是旧槽位，1 是新槽位。unbounded 允许轻微过冲。
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _itemKeys = <GlobalKey>[];

  /// 每个槽位相对 Stack 的矩形（post-frame 量出来）。
  List<Rect> _slots = const <Rect>[];

  /// 每项的选中进度：动画起点 / 终点。稳态时两者相同。
  List<double> _fromWeights = const <double>[];
  List<double> _toWeights = const <double>[];

  /// 胶囊的起点 / 终点矩形；都为空表示还没有几何信息。
  Rect? _fromRect;
  Rect? _toRect;

  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    _fromWeights = _toWeights = _targetWeights();
  }

  @override
  void didUpdateWidget(SlidingSelectionTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount != oldWidget.itemCount) {
      // 选项集合变了：旧坐标已失效，等下一次量完直接钉到目标。
      _slots = const <Rect>[];
      _fromRect = _toRect = null;
      _fromWeights = _toWeights = _targetWeights();
      _controller.value = 1;
      return;
    }
    if (widget.position != null) {
      if (oldWidget.position == null && _controller.isAnimating) {
        _controller.stop();
        _controller.value = 1;
      }
      return;
    }
    if (oldWidget.position != null) {
      _snapToTarget();
      return;
    }
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _animateToTarget(AppMotion.of(context));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.of(context).enabled && _controller.isAnimating) {
      _snapToTarget();
    }
  }

  void _snapToTarget() {
    _fromRect = _toRect = _targetRect();
    _fromWeights = _toWeights = _targetWeights();
    _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 目标槽位每个选项应有的选中进度。
  List<double> _targetWeights() =>
      targetSlotWeights(widget.itemCount, widget.selectedIndex);

  /// 目标胶囊矩形（相对 Stack）；没有选中项或还没量到几何时为 null。
  Rect? _targetRect() {
    final index = widget.selectedIndex;
    if (index == null || index < 0 || index >= _slots.length) return null;
    return widget.pillInset.deflateRect(_slots[index]);
  }

  Rect? _currentRect() {
    final from = _fromRect;
    final to = _toRect;
    if (from == null || to == null) return _targetRect();
    return Rect.lerp(from, to, _controller.value);
  }

  List<double> _currentWeights() => lerpSlotWeights(
    _fromWeights,
    _toWeights,
    widget.itemCount,
    _controller.value,
    widget.selectedIndex,
  );

  /// 从胶囊当前所在位置弹到新选中项；中断时会接着当前位置走，不跳。
  void _animateToTarget(AppMotion motion) {
    final currentWeights = _currentWeights();
    final currentRect = _currentRect();
    final targetRect = _targetRect();

    _fromWeights = currentWeights;
    _toWeights = _targetWeights();
    if (targetRect == null) {
      // 取消选中：胶囊原地淡出。
      _fromRect = _toRect = currentRect;
    } else {
      _fromRect = currentRect ?? targetRect;
      _toRect = targetRect;
    }

    if (!motion.enabled) {
      _fromRect = _toRect;
      _fromWeights = _toWeights;
      _controller.value = 1;
      return;
    }
    _controller.value = 0;
    _controller.animateWith(SpringSimulation(motion.snappy, 0, 1, 0));
  }

  /// 布局完成后量一次槽位；等分 / 横向滚动两种排版都靠它对齐。
  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      _measure();
    });
  }

  void _measure() {
    if (!mounted) return;
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;

    final slots = <Rect>[];
    for (var i = 0; i < widget.itemCount; i++) {
      final box = _itemKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final offset = box.localToGlobal(Offset.zero, ancestor: stackBox);
      slots.add(offset & box.size);
    }
    if (sameSlotRects(slots, _slots)) return;

    final motion = AppMotion.of(context);
    final currentRect = _currentRect();
    final currentWeights = _currentWeights();
    final wasAnimating = _controller.isAnimating;

    setState(() {
      _slots = slots;
      if (widget.position != null) return;
      final targetRect = _targetRect();
      if (!motion.enabled ||
          !wasAnimating ||
          currentRect == null ||
          targetRect == null) {
        _snapToTarget();
        return;
      }
      // 动画中布局变了（字体宽度等）：从当前摆位续弹到新目标。
      _fromRect = currentRect;
      _toRect = targetRect;
      _fromWeights = currentWeights;
      _toWeights = _targetWeights();
      _controller.value = 0;
      _controller.animateWith(SpringSimulation(motion.snappy, 0, 1, 0));
    });
  }

  void _ensureItemKeys() {
    while (_itemKeys.length < widget.itemCount) {
      _itemKeys.add(GlobalKey(debugLabel: 'sliding-item-${_itemKeys.length}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    _ensureItemKeys();
    _scheduleMeasure();

    final content = AnimatedBuilder(
      animation: widget.position ?? _controller,
      builder: (BuildContext context, Widget? child) =>
          _buildTrack(context, motion),
    );

    if (!widget.scrollable) {
      return Padding(padding: widget.padding, child: content);
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: content,
    );
  }

  Widget _buildTrack(BuildContext context, AppMotion motion) {
    final external = widget.position;
    final resolved = external == null
        ? null
        : resolveContinuousSelection(
            position: external.value,
            itemCount: widget.itemCount,
            slots: _slots,
            pillInset: widget.pillInset,
            motionEnabled: motion.enabled,
          );
    final weights = resolved?.weights ?? _currentWeights();
    final pillRect = resolved != null ? resolved.pillRect : _currentRect();
    final opacity = weights
        .fold<double>(0, (double sum, double weight) => sum + weight)
        .clamp(0.0, 1.0);

    return Stack(
      key: _stackKey,
      children: <Widget>[
        if (pillRect != null && opacity > 0)
          Positioned.fromRect(
            rect: pillRect,
            child: IgnorePointer(
              // 稳态（opacity == 1）不要套 Opacity：它按 alpha > 0 就会建
              // 合成层，整条导航条的栅格化都会跟着变（黄金图抓得到）。
              child: opacity >= 1
                  ? _buildPill()
                  : Opacity(opacity: opacity, child: _buildPill()),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < widget.itemCount; i++) ...<Widget>[
              if (i > 0) SizedBox(width: widget.gap),
              if (widget.scrollable)
                _item(context, i, weights[i])
              else
                Expanded(child: _item(context, i, weights[i])),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPill() => DecoratedBox(
    key: const Key('sliding-selection-pill'),
    decoration: ShapeDecoration(
      shape: widget.pillShape,
      color: widget.pillColor,
    ),
  );

  Widget _item(BuildContext context, int index, double selection) {
    return KeyedSubtree(
      key: _itemKeys[index],
      child: widget.itemBuilder(context, index, selection),
    );
  }
}
