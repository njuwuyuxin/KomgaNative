/// 超高条漫长图（> 4096px）纵向分片几何计算（LMB-02）。
///
/// 本地韩漫/国漫拼接条漫常出现 `1080 × 15000` 甚至更高的单张长图，
/// 直接按单张纹理挂载不仅会超出部分移动设备的 `GL_MAX_TEXTURE_SIZE`（4096/8192）导致黑屏，
/// 还会让 `ListView` 把整张 15000px 的 item 一次性常驻内存。
/// 本模块把超高长图切为连续无缝的纵向分片区间，供绘制层按视口虚拟化懒渲染。
library;

import 'package:yomu_reader/src/vertical.dart';

/// 触发长图自动分片的源图像素高度阈值。
const int kTallImageTriggerHeight = 4096;

/// 每个分片的最大源图像素高度（安全低于 4096 纹理上限，同时让 ListView 颗粒度适中）。
const int kTallImageMaxTileHeight = 2048;

/// 超长图中的一个纵向切片（源图像素闭开区间 `[srcTop, srcBottom)`）。
final class TallImageTile {
  const TallImageTile({
    required this.index,
    required this.srcTop,
    required this.srcBottom,
    required this.totalWidth,
    required this.totalHeight,
  });

  final int index;
  final int srcTop;
  final int srcBottom;
  final int totalWidth;
  final int totalHeight;

  int get srcHeight => srcBottom - srcTop;

  double get topFraction => totalHeight <= 0 ? 0.0 : srcTop / totalHeight;

  double get bottomFraction => totalHeight <= 0 ? 1.0 : srcBottom / totalHeight;

  double get heightFraction => totalHeight <= 0 ? 0.0 : srcHeight / totalHeight;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TallImageTile &&
          other.index == index &&
          other.srcTop == srcTop &&
          other.srcBottom == srcBottom &&
          other.totalWidth == totalWidth &&
          other.totalHeight == totalHeight);

  @override
  int get hashCode =>
      Object.hash(index, srcTop, srcBottom, totalWidth, totalHeight);

  @override
  String toString() =>
      'TallImageTile(#$index, [$srcTop, $srcBottom) of ${totalWidth}x$totalHeight)';
}

/// 当源图高度超过 [triggerHeight] 时，切分为若干高度 ≤ [maxTileHeight] 的无缝纵向分片。
///
/// 尺寸非法、未知或未超阈值时返回空列表（按普通整页渲染）。
List<TallImageTile> computeTallImageTiles({
  required int width,
  required int height,
  int triggerHeight = kTallImageTriggerHeight,
  int maxTileHeight = kTallImageMaxTileHeight,
}) {
  if (width <= 0 || height <= 0 || maxTileHeight <= 0) {
    return const <TallImageTile>[];
  }
  if (height <= triggerHeight) {
    return const <TallImageTile>[];
  }
  final tiles = <TallImageTile>[];
  var top = 0;
  var idx = 0;
  while (top < height) {
    final bottom = (top + maxTileHeight) < height
        ? (top + maxTileHeight)
        : height;
    tiles.add(
      TallImageTile(
        index: idx++,
        srcTop: top,
        srcBottom: bottom,
        totalWidth: width,
        totalHeight: height,
      ),
    );
    top = bottom;
  }
  return List<TallImageTile>.unmodifiable(tiles);
}

/// 纵向条漫 `ListView` 展平后的单条渲染槽位。
///
/// 普通页对应 1 个 `tile == null` 的槽位；超高长图展开为多个连续的 `tile != null` 槽位，
/// 且同一页所有槽位的 [displayHeight] 之和严格等于 `VerticalLayout.pageHeights[pageIndex]`，
/// 保证滚轮偏移、跳页与中心页码换算零漂移。
final class VerticalRenderSlot {
  const VerticalRenderSlot({
    required this.pageIndex,
    required this.displayHeight,
    this.tile,
  });

  final int pageIndex;
  final double displayHeight;
  final TallImageTile? tile;

  bool get isTiled => tile != null;
}

/// 将 [layout] 的每一页按源尺寸展平为纵向渲染槽位列表。
List<VerticalRenderSlot> buildVerticalRenderSlots({
  required VerticalLayout layout,
  required ({int? width, int? height}) Function(int index) sizeAt,
  int triggerHeight = kTallImageTriggerHeight,
  int maxTileHeight = kTallImageMaxTileHeight,
}) {
  final slots = <VerticalRenderSlot>[];
  for (var i = 0; i < layout.pageHeights.length; i++) {
    final totalDisplayH = layout.pageHeights[i];
    final size = sizeAt(i);
    final w = size.width;
    final h = size.height;
    final tiles = (w != null && h != null)
        ? computeTallImageTiles(
            width: w,
            height: h,
            triggerHeight: triggerHeight,
            maxTileHeight: maxTileHeight,
          )
        : const <TallImageTile>[];
    if (tiles.isEmpty) {
      slots.add(VerticalRenderSlot(pageIndex: i, displayHeight: totalDisplayH));
      continue;
    }
    var accumulated = 0.0;
    for (var t = 0; t < tiles.length; t++) {
      final tile = tiles[t];
      // 最后一片吃掉浮点舍入尾差，保证整页总高度与 VerticalLayout 严格相等。
      final sliceH = t == tiles.length - 1
          ? (totalDisplayH - accumulated).clamp(0.0, totalDisplayH)
          : totalDisplayH * tile.heightFraction;
      accumulated += sliceH;
      slots.add(
        VerticalRenderSlot(pageIndex: i, displayHeight: sliceH, tile: tile),
      );
    }
  }
  return List<VerticalRenderSlot>.unmodifiable(slots);
}
