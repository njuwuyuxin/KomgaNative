import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 单页 / 双页的绘制层。
///
/// 一个"跨页"就是屏幕上要同时显示的那 1–2 页；单页模式只是长度为 1 的特例，
/// 所以缩放、平移、点击区、图片加载都在这里共用一套，不用写两遍。
/// 翻页/进度/模式切换由 `ReaderScreen` 管——这里只负责"把当前的跨页画好"。
class ReaderPagedView extends StatefulWidget {
  const ReaderPagedView({
    required this.bookId,
    required this.pages,
    required this.spread,
    required this.rightToLeft,
    required this.palette,
    required this.onTurn,
    required this.onToggleChrome,
    super.key,
  });

  final String bookId;

  /// 全书页元数据（尺寸未知时按 [kFallbackPageWidth] × [kFallbackPageHeight] 处理）。
  final List<PageInfo> pages;

  /// 当前跨页包含的 **0 基**页索引，1–2 个。
  final List<int> spread;

  final bool rightToLeft;
  final ReaderPalette palette;

  /// 翻页请求：-1 上一屏，+1 下一屏（由外部决定是"一页"还是"一跨页"）。
  final ValueChanged<int> onTurn;

  final VoidCallback onToggleChrome;

  @override
  State<ReaderPagedView> createState() => _ReaderPagedViewState();
}

/// 服务端没返回尺寸时的兜底页面尺寸（比例接近实体漫画单页）。
const int kFallbackPageWidth = 1000;
const int kFallbackPageHeight = 1500;

class _ReaderPagedViewState extends State<ReaderPagedView> {
  /// 指针移动超过这个距离就不算点击（拖拽/缩放）。
  static const double _tapSlop = 12;

  double _zoom = 1;
  Offset _pan = Offset.zero;
  Offset _startFocal = Offset.zero;
  double _startZoom = 1;

  // 手势回调里拿不到 LayoutBuilder 的 constraints，所以 build 时缓存一份：
  // 缩放要以焦点为基准，需要"缩放前的有效比例 + 内容左上角"。
  int _pageWidth = kFallbackPageWidth;
  int _pageHeight = kFallbackPageHeight;
  SizeD _viewport = const SizeD(0, 0);
  double _startScale = 1;
  Offset _startContent = Offset.zero;

  /// 点击判定用自己的指针记账：`onTapUp` 与 `onScaleStart/Update` 在同一个
  /// gesture arena 里会互相抢，实测 tap 会被 scale 吃掉，翻页完全不响应。
  int _activePointers = 0;
  Offset? _downAt;

  @override
  void didUpdateWidget(ReaderPagedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了一屏就复位：上一屏的缩放/平移套到新页上会看到莫名其妙的位置。
    if (!_sameSpread(oldWidget.spread, widget.spread)) {
      _zoom = 1;
      _pan = Offset.zero;
    }
  }

  static bool _sameSpread(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startZoom = _zoom;
    _startFocal = details.localFocalPoint;
    final layout = computePagedLayout(
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      viewport: _viewport,
      zoomFactor: _zoom,
      panX: _pan.dx,
      panY: _pan.dy,
    );
    _startScale = layout.scale;
    _startContent = Offset(layout.content.left, layout.content.top);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final nextZoom = (_startZoom * details.scale).clamp(1.0, 4.0);
    if (nextZoom <= 1.0) {
      setState(() {
        _zoom = nextZoom;
        // 缩回适配尺寸时内容居中，旧平移没有意义。
        _pan = Offset.zero;
      });
      return;
    }

    // 先用引擎算出"缩放后的有效比例"，再以两指中点为基准反推新的内容左上角。
    // 直接用 zoomFactor 当比例会忽略夹紧（fit 很小时 max 可能小于 fit*4）。
    final nextScale = computePagedLayout(
      pageWidth: _pageWidth,
      pageHeight: _pageHeight,
      viewport: _viewport,
      zoomFactor: nextZoom,
    ).scale;
    final origin = zoomAboutFocal(
      contentLeft: _startContent.dx,
      contentTop: _startContent.dy,
      scale: _startScale,
      nextScale: nextScale,
      focalX: _startFocal.dx,
      focalY: _startFocal.dy,
      // 焦点本身也可以移动：单指拖动时比例不变，等价于平移。
      focalDeltaX: details.localFocalPoint.dx - _startFocal.dx,
      focalDeltaY: details.localFocalPoint.dy - _startFocal.dy,
    );
    setState(() {
      _zoom = nextZoom;
      _pan = Offset(origin.left, origin.top);
    });
  }

  void _onTap(double dx, double width) {
    final fraction = width <= 0 ? 0.5 : dx / width;
    if (fraction < 0.33) {
      // 左侧三分之一：LTR 往回翻，RTL 往前翻（日漫）。
      widget.onTurn(widget.rightToLeft ? 1 : -1);
    } else if (fraction > 0.67) {
      widget.onTurn(widget.rightToLeft ? -1 : 1);
    } else {
      widget.onToggleChrome();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 视觉顺序：RTL 时后一页在左，所以渲染顺序要反过来。
    final order = visualOrder(widget.spread, rightToLeft: widget.rightToLeft);
    final sizes = <int, int>{};
    for (final index in order) {
      final info = widget.pages[index];
      sizes[index] = info.width ?? kFallbackPageWidth;
    }
    final totalWidth = sizes.values.fold<int>(0, (sum, w) => sum + w);
    var maxHeight = kFallbackPageHeight;
    for (final index in order) {
      final h = widget.pages[index].height ?? kFallbackPageHeight;
      if (h > maxHeight) maxHeight = h;
    }

    // 手势回调要用：页面像素尺寸（跨页合计）在 build 时确定。
    _pageWidth = totalWidth;
    _pageHeight = maxHeight;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final viewport = SizeD(constraints.maxWidth, constraints.maxHeight);
        _viewport = viewport;
        final layout = computePagedLayout(
          pageWidth: totalWidth,
          pageHeight: maxHeight,
          viewport: viewport,
          zoomFactor: _zoom,
          panX: _pan.dx,
          panY: _pan.dy,
        );
        return Listener(
          key: const Key('reader-tap-layer'),
          onPointerDown: (PointerDownEvent event) {
            _activePointers++;
            _downAt = _activePointers == 1 ? event.localPosition : null;
          },
          onPointerUp: (PointerUpEvent event) {
            if (_activePointers > 0) _activePointers--;
            final down = _downAt;
            _downAt = null;
            if (down == null || _activePointers > 0) return;
            // 移动超过阈值视为拖拽/缩放，不当作翻页点击。
            if ((event.localPosition - down).distance > _tapSlop) return;
            _onTap(down.dx, constraints.maxWidth);
          },
          onPointerCancel: (PointerCancelEvent event) {
            _activePointers = 0;
            _downAt = null;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: Stack(
              children: <Widget>[
                if (layout.content.width > 0 && layout.content.height > 0)
                  Positioned(
                    left: layout.content.left,
                    top: layout.content.top,
                    width: layout.content.width,
                    height: layout.content.height,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final index in order)
                          Expanded(
                            flex: sizes[index]!,
                            child: ReaderPage(
                              bookId: widget.bookId,
                              pageIndex: index,
                              palette: widget.palette,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 单页图片（含加载中/失败/重试）。
class ReaderPage extends ConsumerWidget {
  const ReaderPage({
    required this.bookId,
    required this.pageIndex,
    required this.palette,
    super.key,
  });

  final String bookId;

  /// 0 基页索引。
  final int pageIndex;

  final ReaderPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = (bookId: bookId, page: pageIndex + 1);
    final async = ref.watch(readerPageImageProvider(request));
    final Uint8List? bytes = async.value;
    final error = async.error;

    if (bytes != null) {
      return Image.memory(
        bytes,
        key: Key('reader-image-$pageIndex'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }
    if (error != null) {
      return Center(
        child: PageError(
          error: error,
          palette: palette,
          onRetry: () => ref.invalidate(readerPageImageProvider(request)),
        ),
      );
    }
    return Center(child: CircularProgressIndicator(color: palette.muted));
  }
}
