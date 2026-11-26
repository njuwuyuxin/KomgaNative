/// 宽幅合扫页自动切分（Split Wide Pages）与临时合页纯逻辑（LMB-01）。
///
/// 本地单行本扫图常把左右两页合扫成一张宽幅单图（`w / h > 1.2`）。
/// 在单页翻页模式下开启切分后，每张宽图无损展开为两个连续阅读帧：
/// - `RTL`（日漫）先读右半页，下一拍读左半页；
/// - `LTR`（欧美漫）先读左半页，下一拍读右半页；
/// - 遇到真正跨页插画时，可按 [mergedPageIndex] 对当前物理页临时合页查看整图。
library;

import 'package:yomu_reader/src/layout.dart';
import 'package:yomu_reader/src/spreads.dart';

/// 宽页自动切分策略。
enum WidePageSplitMode {
  /// 关闭：宽页保持整张缩放显示。
  off,

  /// 竖屏自动：仅竖屏单页模式下自动切分宽图，横屏保持完整跨页。
  autoPortrait,

  /// 始终切分：无论横竖屏，只要处于单页翻页模式都切分宽图。
  always,
}

extension WidePageSplitModeX on WidePageSplitMode {
  /// 当前模式与屏幕方向下是否应激活宽页切分。
  bool isActive({required ReadingMode mode, required bool landscape}) {
    if (mode != ReadingMode.paged) return false;
    return switch (this) {
      WidePageSplitMode.off => false,
      WidePageSplitMode.autoPortrait => !landscape,
      WidePageSplitMode.always => true,
    };
  }
}

/// 单页绘制时的水平半幅裁切区域。
enum PageHalf { full, left, right }

extension PageHalfX on PageHalf {
  bool get isSplit => this != PageHalf.full;

  /// 返回在原图宽度坐标系中的水平裁切区间 `[left, right]`（范围 0..1）。
  ({double left, double right}) get horizontalFraction => switch (this) {
    PageHalf.full => (left: 0.0, right: 1.0),
    PageHalf.left => (left: 0.0, right: 0.5),
    PageHalf.right => (left: 0.5, right: 1.0),
  };

  /// 计算切分后的逻辑宽度（用于布局与缩放计算）。
  int effectiveWidth(int rawWidth) {
    if (this == PageHalf.full || rawWidth <= 1) return rawWidth;
    return (rawWidth / 2).round().clamp(1, rawWidth);
  }
}

/// 单页切分后的逻辑阅读帧。
final class SplitFrame {
  const SplitFrame({required this.pageIndex, required this.half});

  /// 0 基物理页索引。
  final int pageIndex;

  /// 水平裁切半幅。
  final PageHalf half;

  /// 1 基物理页码（进度上报与滑杆始终回写物理页码）。
  int get pageNumber => pageIndex + 1;

  bool get isSplit => half.isSplit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SplitFrame &&
          other.pageIndex == pageIndex &&
          other.half == half);

  @override
  int get hashCode => Object.hash(pageIndex, half);

  @override
  String toString() => 'SplitFrame(page: $pageNumber, half: ${half.name})';
}

/// 将 [pageCount] 张物理页展开为有序的阅读帧序列。
///
/// - 普通竖页与未知尺寸页输出 1 帧 [PageHalf.full]；
/// - 宽页（`w / h > wideThreshold`）输出 2 帧：RTL 为 `[right, left]`，LTR 为 `[left, right]`；
/// - 当物理页索引等于 [mergedPageIndex]（用户点击了「临时合页」）时，该页保持 1 帧 [PageHalf.full]。
List<SplitFrame> buildSplitFrames({
  required int pageCount,
  required PageAspect Function(int index) aspectAt,
  required bool rightToLeft,
  double wideThreshold = kDefaultWideAspectThreshold,
  int? mergedPageIndex,
}) {
  if (pageCount <= 0) return const <SplitFrame>[];
  final frames = <SplitFrame>[];
  for (var i = 0; i < pageCount; i++) {
    final isWide = i != mergedPageIndex && aspectAt(i).isWide(wideThreshold);
    if (!isWide) {
      frames.add(SplitFrame(pageIndex: i, half: PageHalf.full));
      continue;
    }
    if (rightToLeft) {
      frames.add(SplitFrame(pageIndex: i, half: PageHalf.right));
      frames.add(SplitFrame(pageIndex: i, half: PageHalf.left));
    } else {
      frames.add(SplitFrame(pageIndex: i, half: PageHalf.left));
      frames.add(SplitFrame(pageIndex: i, half: PageHalf.right));
    }
  }
  return List<SplitFrame>.unmodifiable(frames);
}

/// 查找物理页 [pageIndex] 在 [frames] 中首次出现的帧下标；未找到返回 -1。
int firstSplitFrameIndex(List<SplitFrame> frames, int pageIndex) {
  for (var i = 0; i < frames.length; i++) {
    if (frames[i].pageIndex == pageIndex) return i;
  }
  return -1;
}

/// 根据物理页与期望半幅定位当前帧下标（供切方向、临时合页或外部跳页稳定回落）。
int resolveSplitFrameIndex(
  List<SplitFrame> frames, {
  required int pageIndex,
  PageHalf? preferredHalf,
}) {
  if (frames.isEmpty) return -1;
  if (preferredHalf != null) {
    for (var i = 0; i < frames.length; i++) {
      if (frames[i].pageIndex == pageIndex && frames[i].half == preferredHalf) {
        return i;
      }
    }
  }
  final first = firstSplitFrameIndex(frames, pageIndex);
  if (first >= 0) return first;
  return pageIndex.clamp(0, frames.length - 1);
}
