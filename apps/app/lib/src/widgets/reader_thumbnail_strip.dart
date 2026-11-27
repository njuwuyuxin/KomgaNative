import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/physics.dart' show SpringSimulation;
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/widgets/page_thumbnail.dart';
import 'package:yomu/src/features/reader/reader_layout.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

part 'reader_thumbnail_strip_item.dart';

/// 底栏上方的横向页缩略图滑条（UI-P1-2）。
///
/// 支持紧凑 / 放大两档缩略图尺寸：在滑条上**上滑**平滑放大（单张更大、一行显示更少），
/// **下滑**平滑缩回紧凑档；拖动与松手落位全程以当前居中页为锚点，不左右跳动。
///
/// 三条约束：
/// - **按屏分组**：双页模式下一条缩略图代表一跨页，和翻页粒度一致（见 [ReaderLayout.screenAt]）；
/// - **懒加载**：`ListView.builder` + 固定 `itemExtent`，只有可见范围内的实例会被构建；
/// - **方向镜像**：RTL 用 `reverse: true`，起点在右侧，和翻页方向一致。
class ReaderThumbnailStrip extends StatefulWidget {
  const ReaderThumbnailStrip({
    required this.bookId,
    required this.layout,
    required this.palette,
    required this.onJump,
    this.onGroupFrom,
    this.onSharePage,
    this.rightToLeft = false,
    super.key,
  });

  final String bookId;
  final ReaderLayout layout;
  final ReaderPalette palette;

  /// 点了某一屏：回调 1 基页码。
  final ValueChanged<int> onJump;

  /// 双页模式长按某一屏："从这一页开始重新配对"（UI-P3-5）。
  final ValueChanged<int>? onGroupFrom;

  /// 长按某一屏分享该页（UI-P3-6）。
  final Future<void> Function(int page)? onSharePage;

  final bool rightToLeft;

  @override
  State<ReaderThumbnailStrip> createState() => _ReaderThumbnailStripState();
}

class _ReaderThumbnailStripState extends State<ReaderThumbnailStrip>
    with SingleTickerProviderStateMixin {
  final ScrollController _controller = ScrollController();

  /// 两档缩放进度：0 = 紧凑档，1 = 放大档。
  late final AnimationController _expand = AnimationController(vsync: this)
    ..addListener(_onExpandTick);

  /// 视口宽度：居中偏移要它才能算（`LayoutBuilder` 里缓存）。
  double _viewport = 0;

  /// 上一次自动居中到的下标；当前页变了就重新居中。
  int _centered = 0;

  /// 上一次触发触感反馈的下标（拖动时每经过一屏振一次）。
  int _haptic = -1;

  /// 当前是否处于放大档（供松手判定是否切换档位并触发触感）。
  bool _expanded = false;

  /// 缩放过程中锁定的逻辑位置锚点（条目下标 + 视口内相对位置），
  /// 避免 `itemExtent` 变化时列表横向漂移（首尾贴边、中部居中）。
  ({double item, double screenFraction})? _resizeAnchor;

  static const double _kFlingVelocity = 250;

  double get _t => _expand.value.clamp(0.0, 1.0);
  double _thumbWidth(double t) =>
      lerpDouble(AppSizes.thumb.width, AppSizes.thumbExpanded.width, t)!;
  double _thumbHeight(double t) =>
      lerpDouble(AppSizes.thumb.height, AppSizes.thumbExpanded.height, t)!;
  double _gap(double t) => lerpDouble(AppSpacing.xs, AppSpacing.sm, t)!;
  double _extentAt(double t) => _thumbWidth(t) + _gap(t);
  double _stripHeight(double t) => lerpDouble(
    AppSizes.thumbStripHeight,
    AppSizes.thumbStripExpandedHeight,
    t,
  )!;

  @override
  void initState() {
    super.initState();
    _centered = widget.layout.screenIndex;
    _scheduleCenter();
  }

  @override
  void didUpdateWidget(ReaderThumbnailStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = widget.layout.screenIndex;
    if (index == _centered) return;
    _centered = index;
    _scheduleCenter();
  }

  @override
  void dispose() {
    _expand.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onExpandTick() {
    setState(() {});
    _syncAnchor();
  }

  void _syncAnchor() {
    final anchor = _resizeAnchor;
    if (anchor == null || !_controller.hasClients || _viewport <= 0) return;
    final target = _offsetForAnchor(anchor, _t);
    if (target <= _controller.position.maxScrollExtent) {
      _controller.jumpTo(target);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final current = _resizeAnchor;
      if (current != null) _controller.jumpTo(_offsetForAnchor(current, _t));
    });
  }

  ({double item, double screenFraction}) _captureAnchor(double t) {
    if (!_controller.hasClients || _viewport <= 0) {
      return (item: _centered.toDouble(), screenFraction: 0.5);
    }
    final max = _controller.position.maxScrollExtent;
    final offset = _controller.offset;
    final half = _viewport / 2;
    final double fraction;
    if (max <= 0) {
      fraction = 0.0;
    } else if (offset < half) {
      fraction = (offset / half) * 0.5;
    } else if (max - offset < half) {
      fraction = 1.0 - ((max - offset) / half) * 0.5;
    } else {
      fraction = 0.5;
    }
    final item = (offset + fraction * _viewport) / _extentAt(t);
    return (item: item, screenFraction: fraction);
  }

  double _offsetForAnchor(
    ({double item, double screenFraction}) anchor,
    double t,
  ) {
    final extent = _extentAt(t);
    final limit = (widget.layout.screenCount * extent - _viewport).clamp(
      0.0,
      double.infinity,
    );
    final target = anchor.item * extent - anchor.screenFraction * _viewport;
    return target.clamp(0.0, limit);
  }

  void _scheduleCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerTo(_centered, animate: false);
    });
  }

  double _offsetForFraction(double index, double t) {
    final extent = _extentAt(t);
    final limit = (widget.layout.screenCount * extent - _viewport).clamp(
      0.0,
      double.infinity,
    );
    final target = index * extent - (_viewport - _thumbWidth(t)) / 2;
    return target.clamp(0.0, limit);
  }

  void _centerTo(int index, {required bool animate}) {
    if (!_controller.hasClients || _viewport <= 0) return;
    final target = _offsetForFraction(index.toDouble(), _t);
    final motion = AppMotion.of(context);
    if (!animate || !motion.enabled) {
      _controller.jumpTo(target);
      return;
    }
    unawaited(
      _controller.animateTo(
        target,
        duration: motion.standard,
        curve: motion.standardCurve,
      ),
    );
  }

  void _onVerticalDragStart(DragStartDetails _) {
    _expand.stop();
    _resizeAnchor = _captureAnchor(_t);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    const span = AppSizes.thumbStripExpandedHeight - AppSizes.thumbStripHeight;
    if (span <= 0) return;
    _expand.value = (_expand.value - details.delta.dy / span).clamp(0.0, 1.0);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final targetExpanded = velocity < -_kFlingVelocity
        ? true
        : (velocity > _kFlingVelocity ? false : _expand.value >= 0.5);
    _settleExpand(targetExpanded, velocityPx: -velocity);
  }

  void _onVerticalDragCancel() => _settleExpand(_expand.value >= 0.5);

  void _toggleExpanded() {
    _resizeAnchor = _captureAnchor(_t);
    _settleExpand(!_expanded);
  }

  void _settleExpand(bool targetExpanded, {double velocityPx = 0}) {
    if (targetExpanded != _expanded) {
      _expanded = targetExpanded;
      unawaited(AppHaptics.selection());
    }
    final target = targetExpanded ? 1.0 : 0.0;
    final motion = AppMotion.of(context);
    if (!motion.enabled) {
      _expand.value = target;
      _syncAnchor();
      _resizeAnchor = null;
      return;
    }
    const span = AppSizes.thumbStripExpandedHeight - AppSizes.thumbStripHeight;
    final sim = SpringSimulation(
      motion.snappy,
      _expand.value,
      target,
      span > 0 ? velocityPx / span : 0.0,
    );
    unawaited(
      _expand.animateWith(sim).whenComplete(() {
        if (mounted) _resizeAnchor = null;
      }),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    if (notification.dragDetails == null || _viewport <= 0) return false;
    final t = _t;
    final center =
        (notification.metrics.pixels + (_viewport - _thumbWidth(t)) / 2) /
        _extentAt(t);
    final index = center.round().clamp(0, widget.layout.screenCount - 1);
    if (index == _haptic) return false;
    _haptic = index;
    unawaited(AppHaptics.selection());
    return false;
  }

  String _label(List<int> pages) => pages.length > 1
      ? '${pages.first + 1}–${pages.last + 1}'
      : '${pages.first + 1}';

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final t = _t;
    final thumbW = _thumbWidth(t);
    final thumbH = _thumbHeight(t);
    final gap = _gap(t);
    final cacheWidth =
        (AppSizes.thumbExpanded.width * MediaQuery.devicePixelRatioOf(context))
            .round();
    return GestureDetector(
      key: const Key('reader-thumb-resize-area'),
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: _onVerticalDragStart,
      onVerticalDragUpdate: _onVerticalDragUpdate,
      onVerticalDragEnd: _onVerticalDragEnd,
      onVerticalDragCancel: _onVerticalDragCancel,
      child: SizedBox(
        height: _stripHeight(t),
        child: Column(
          children: <Widget>[
            _StripGrabber(palette: widget.palette, onTap: _toggleExpanded),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  _viewport = constraints.maxWidth;
                  return NotificationListener<ScrollNotification>(
                    onNotification: _onScroll,
                    child: ListView.builder(
                      key: const Key('reader-thumb-strip'),
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      reverse: widget.rightToLeft,
                      itemExtent: thumbW + gap,
                      padding: EdgeInsets.zero,
                      itemCount: layout.screenCount,
                      itemBuilder: (BuildContext context, int index) {
                        final pages = layout.screenAt(index);
                        return _StripThumb(
                          key: Key('reader-thumb-${pages.first + 1}'),
                          bookId: widget.bookId,
                          page: pages.first + 1,
                          label: _label(pages),
                          current: index == layout.screenIndex,
                          palette: widget.palette,
                          width: thumbW,
                          height: thumbH,
                          horizontalPadding: gap / 2,
                          cacheWidth: cacheWidth,
                          onTap: () => widget.onJump(pages.first + 1),
                          onLongPress:
                              widget.onSharePage == null &&
                                  widget.onGroupFrom == null
                              ? null
                              : () => _showThumbnailPageActions(
                                  context,
                                  palette: widget.palette,
                                  page: pages.first + 1,
                                  onSharePage: widget.onSharePage,
                                  onGroupFrom: widget.onGroupFrom,
                                ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
