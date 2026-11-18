import 'dart:async';

import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/widgets/page_thumbnail.dart';
import 'package:komga_native/src/widgets/reader_layout.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 底栏上方的横向页缩略图滑条（UI-P1-2）。
///
/// 与"查看全部"的网格面板（`page_navigator_sheet.dart`）互补：滑条用于邻页微调，
/// 网格用于跳到远处，两者都保留。
///
/// 三条约束：
/// - **按屏分组**：双页模式下一条缩略图代表一跨页，和翻页粒度一致（见 [ReaderLayout.screenAt]）；
/// - **懒加载**：`ListView.builder` + 固定 `itemExtent`，只有可见范围内的实例会被构建，
///   也才会去请求页图字节；
/// - **方向镜像**：RTL 用 `reverse: true`，起点在右侧，和翻页方向一致。
class ReaderThumbnailStrip extends StatefulWidget {
  const ReaderThumbnailStrip({
    required this.bookId,
    required this.layout,
    required this.palette,
    required this.onJump,
    this.rightToLeft = false,
    super.key,
  });

  final String bookId;
  final ReaderLayout layout;
  final ReaderPalette palette;

  /// 点了某一屏：回调 1 基页码。
  final ValueChanged<int> onJump;

  final bool rightToLeft;

  @override
  State<ReaderThumbnailStrip> createState() => _ReaderThumbnailStripState();
}

class _ReaderThumbnailStripState extends State<ReaderThumbnailStrip> {
  final ScrollController _controller = ScrollController();

  /// 视口宽度：居中偏移要它才能算（`LayoutBuilder` 里缓存）。
  double _viewport = 0;

  /// 上一次自动居中到的下标；当前页变了就重新居中。
  int _centered = 0;

  /// 上一次触发触感反馈的下标（拖动时每经过一屏振一次）。
  int _haptic = -1;

  double get _extent => AppSizes.thumb.width + AppSpacing.xs;

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
    _controller.dispose();
    super.dispose();
  }

  /// 等这一帧布局完再滚：`initState` 里还没有视口宽度。
  void _scheduleCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerTo(_centered, animate: false);
    });
  }

  double _offsetFor(int index) {
    final count = widget.layout.screenCount;
    final limit = (count * _extent - _viewport).clamp(0.0, double.infinity);
    final target = index * _extent - (_viewport - AppSizes.thumb.width) / 2;
    return target.clamp(0.0, limit);
  }

  void _centerTo(int index, {required bool animate}) {
    if (!_controller.hasClients || _viewport <= 0) return;
    final target = _offsetFor(index);
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

  /// 拖动时"每经过一屏"给一次 selection 触感。
  bool _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    if (notification.dragDetails == null || _viewport <= 0) return false;
    final center =
        (notification.metrics.pixels + (_viewport - AppSizes.thumb.width) / 2) /
        _extent;
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
    // 缩略图按显示尺寸 ×DPR 解码：既够清晰，又不会把整页原图塞进内存。
    final cacheWidth =
        (AppSizes.thumb.width * MediaQuery.devicePixelRatioOf(context)).round();
    return SizedBox(
      height: AppSizes.thumbStripHeight,
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
              itemExtent: _extent,
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
                  cacheWidth: cacheWidth,
                  onTap: () => widget.onJump(pages.first + 1),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _StripThumb extends StatelessWidget {
  const _StripThumb({
    required this.bookId,
    required this.page,
    required this.label,
    required this.current,
    required this.palette,
    required this.cacheWidth,
    required this.onTap,
    super.key,
  });

  final String bookId;
  final int page;
  final String label;
  final bool current;
  final ReaderPalette palette;
  final int cacheWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.xs);
    return Semantics(
      container: true,
      button: true,
      selected: current,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Center(
              child: SizedBox(
                width: AppSizes.thumb.width,
                height: AppSizes.thumb.height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: radius,
                    border: Border.all(
                      color: current ? palette.foreground : palette.outline,
                      width: current
                          ? AppSizes.hairline * 2
                          : AppSizes.hairline,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: PageThumbnailImage(
                      bookId: bookId,
                      page: page,
                      palette: palette,
                      cacheWidth: cacheWidth,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
