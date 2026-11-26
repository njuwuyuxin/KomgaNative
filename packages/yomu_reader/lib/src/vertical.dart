/// 纵向连续（webtoon / 条漫）模式的几何计算。
///
/// 与双页一样保持纯函数：给定"每页宽高比 + 视口宽度"就能算出每页的高度和位置，
/// 于是"滚到哪一页了"和"跳到第 N 页要滚多少"都能在纯 Dart 里单测，
/// 不需要起 Flutter、更不需要真的滚一下。
library;

import 'spreads.dart';

/// 尺寸未知时的兜底宽高比（宽/高）。漫画单页大约 0.65–0.75，取中间值。
///
/// 兜底值只影响"还没加载出图时的占位高度"和滚动位置估算；
/// 真正的页面高度以服务端返回的 `width/height` 为准。
const double kDefaultAspectRatio = 0.7;

/// 纵向连续模式的布局结果。
class VerticalLayout {
  const VerticalLayout({
    required this.pageHeights,
    required this.offsets,
    required this.totalHeight,
  });

  static const VerticalLayout empty = VerticalLayout(
    pageHeights: <double>[],
    offsets: <double>[],
    totalHeight: 0,
  );

  /// 每页按视口宽度等比缩放后的高度。
  final List<double> pageHeights;

  /// 每页顶部相对内容顶部的偏移（与 [pageHeights] 等长）。
  final List<double> offsets;

  /// 全部内容的高度（不含最后一页之后的间距）。
  final double totalHeight;

  int get pageCount => pageHeights.length;
  bool get isEmpty => pageHeights.isEmpty;

  /// 第 [index] 页的顶部偏移；越界返回 0。
  double offsetOf(int index) {
    if (index < 0 || index >= offsets.length) return 0;
    return offsets[index];
  }

  double heightOf(int index) {
    if (index < 0 || index >= pageHeights.length) return 0;
    return pageHeights[index];
  }

  @override
  String toString() =>
      'VerticalLayout($pageCount pages, ${totalHeight.toStringAsFixed(1)}px)';
}

/// 计算纵向连续的布局。
///
/// [viewportWidth] 是可用宽度（页图按宽度铺满）；[gap] 是页间距，默认 0 让条漫连续。
VerticalLayout computeVerticalLayout({
  required int pageCount,
  required double viewportWidth,
  required PageAspect Function(int index) aspectAt,
  double gap = 0,
  double fallbackAspectRatio = kDefaultAspectRatio,
}) {
  if (pageCount <= 0) return VerticalLayout.empty;

  final heights = <double>[];
  final offsets = <double>[];
  var y = 0.0;

  for (var i = 0; i < pageCount; i++) {
    final ratio = aspectAt(i).ratio ?? fallbackAspectRatio;
    final height = viewportWidth <= 0 ? 0.0 : viewportWidth / ratio;
    offsets.add(y);
    heights.add(height);
    y += height + gap;
  }

  return VerticalLayout(
    pageHeights: List<double>.unmodifiable(heights),
    offsets: List<double>.unmodifiable(offsets),
    totalHeight: heights.isEmpty ? 0 : y - gap,
  );
}

/// 视口中心落在哪一页（0 基）。
///
/// 为什么用"中心"而不是"顶部"：条漫一屏可能只露出半页，
/// 用顶部会在页缝隙里来回跳，进度看起来像在抽搐。
/// 越界（滚过头/回弹负数）一律夹到第一页或最后一页。
int pageAtViewportCenter(
  VerticalLayout layout, {
  required double scrollOffset,
  required double viewportHeight,
}) {
  if (layout.isEmpty) return 0;

  final total = layout.totalHeight;
  final center = (scrollOffset + viewportHeight / 2).clamp(0.0, total);
  if (layout.pageCount == 1) return 0;

  // 二分：找最后一个 offsets[i] <= center 的 i。
  var low = 0;
  var high = layout.offsets.length - 1;
  while (low < high) {
    final mid = (low + high + 1) >> 1;
    if (layout.offsets[mid] <= center) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return low;
}

/// 跳到第 [index] 页时需要的滚动偏移：让该页顶部对齐视口顶部。
double scrollOffsetForPage(VerticalLayout layout, int index) {
  if (layout.isEmpty) return 0;
  final clamped = index.clamp(0, layout.pageCount - 1);
  return layout.offsets[clamped];
}

/// 自动滚动速度档位（RDR-08）：1–10 档。
///
/// 映射成"每秒滚多少逻辑像素"：1 档 60 px/s（慢慢看跨页大图），
/// 10 档 240 px/s（接近快速翻条漫）。范围故意压得保守——
/// 快的档位交给人手动滑，自动滚动再快就只是晃眼。
double autoScrollPixelsPerSecond(int speed) {
  final clamped = speed.clamp(1, 10);
  return 40 + clamped * 20;
}

/// 一帧应该滚多少（用真实帧间隔，滚动速度才不会随帧率变化）。
double autoScrollDeltaForFrame(int speed, Duration frame) {
  final seconds = frame.inMicroseconds / Duration.microsecondsPerSecond;
  return autoScrollPixelsPerSecond(speed) * seconds;
}
