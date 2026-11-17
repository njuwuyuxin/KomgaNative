import 'geometry.dart';

/// 单页适配方式。
enum FitMode {
  /// 整页可见（默认）。
  contain,

  /// 宽度铺满，允许纵向滚动/裁切。
  fitWidth,

  /// 高度铺满。
  fitHeight,

  /// 1 物理像素对 1 逻辑像素。
  original,
}

/// 阅读模式。
enum ReadingMode { paged, doublePage, verticalScroll }

/// 一次布局计算的结果。
class PagedLayout {
  const PagedLayout({
    required this.scale,
    required this.minScale,
    required this.maxScale,
    required this.content,
  });

  /// 当前缩放（页面像素 → 逻辑像素）。
  final double scale;

  final double minScale;
  final double maxScale;

  /// 页面在视口中的绘制矩形（已含平移）。
  final RectD content;

  bool get isZoomedIn => scale > minScale * 1.001;

  @override
  String toString() =>
      'PagedLayout(scale: ${scale.toStringAsFixed(3)}, content: $content)';
}

/// 计算某个适配模式下的基准缩放。
///
/// [pageWidth] / [pageHeight] 是页面像素尺寸；[viewport] 是逻辑像素。
double fitScaleFor({
  required int pageWidth,
  required int pageHeight,
  required SizeD viewport,
  required FitMode mode,
}) {
  if (pageWidth <= 0 || pageHeight <= 0 || viewport.isEmpty) return 1;
  final scaleX = viewport.width / pageWidth;
  final scaleY = viewport.height / pageHeight;
  return switch (mode) {
    FitMode.contain => scaleX < scaleY ? scaleX : scaleY,
    FitMode.fitWidth => scaleX,
    FitMode.fitHeight => scaleY,
    FitMode.original => 1.0,
  };
}

/// 计算 paged 模式下的绘制矩形。
///
/// 交互规则（与手势状态机配合，均有单测覆盖）：
/// 1. 缩放范围 `[fit, max(fit * 4, 1)]`；
/// 2. 内容超出视口时按 [pan] 平移并夹紧，保证不出现空白边；
/// 3. 内容小于视口时居中（忽略 pan）。
PagedLayout computePagedLayout({
  required int pageWidth,
  required int pageHeight,
  required SizeD viewport,
  FitMode fit = FitMode.contain,
  ReadingMode mode = ReadingMode.paged,
  double zoomFactor = 1.0,
  double panX = 0,
  double panY = 0,
}) {
  final base = fitScaleFor(
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    viewport: viewport,
    mode: mode == ReadingMode.doublePage ? FitMode.contain : fit,
  );
  final minScale = base;
  final maxScale = base * 4 > 1 ? base * 4 : 1.0;
  final scale = (base * zoomFactor).clamp(minScale, maxScale).toDouble();

  final contentWidth = pageWidth * scale;
  final contentHeight = pageHeight * scale;

  final double left;
  final double top;
  if (contentWidth <= viewport.width) {
    left = (viewport.width - contentWidth) / 2;
  } else {
    final minLeft = viewport.width - contentWidth;
    left = panX.clamp(minLeft, 0.0).toDouble();
  }
  if (contentHeight <= viewport.height) {
    top = (viewport.height - contentHeight) / 2;
  } else {
    final minTop = viewport.height - contentHeight;
    top = panY.clamp(minTop, 0.0).toDouble();
  }

  return PagedLayout(
    scale: scale,
    minScale: minScale,
    maxScale: maxScale,
    content: RectD(left, top, contentWidth, contentHeight),
  );
}
