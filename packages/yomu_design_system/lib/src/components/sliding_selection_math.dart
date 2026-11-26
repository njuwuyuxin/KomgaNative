import 'package:material_ui/material_ui.dart';

/// 按外部连续位置 [position]（范围 `[0, itemCount - 1]`）计算胶囊矩形与各槽位权重。
///
/// 用于与 `TabController.animation` / `PageController` 等连续滚动进度 1:1 同步：
/// - `motionEnabled == true`：在相邻两个槽位间线性插值矩形与权重；
/// - `motionEnabled == false`（墨水屏 / 减少动态效果）：四舍五入瞬切到最近槽位，
///   不产生中间灰阶过渡帧。
///
/// 超出范围的值会被钳位到 `[0, itemCount - 1]`（例如弹性过滚）；
/// 非有限值返回 null，由调用方回退到离散 `selectedIndex`。
({Rect? pillRect, List<double> weights})? resolveContinuousSelection({
  required double position,
  required int itemCount,
  required List<Rect> slots,
  required EdgeInsets pillInset,
  required bool motionEnabled,
}) {
  if (itemCount <= 0 || !position.isFinite) return null;

  final clamped = position.clamp(0.0, (itemCount - 1).toDouble());
  final weights = List<double>.filled(itemCount, 0);

  if (!motionEnabled) {
    final index = clamped.round();
    weights[index] = 1;
    final rect = index < slots.length
        ? pillInset.deflateRect(slots[index])
        : null;
    return (pillRect: rect, weights: weights);
  }

  final lower = clamped.floor();
  final upper = clamped.ceil();
  final t = clamped - lower;

  if (lower == upper) {
    weights[lower] = 1;
  } else {
    weights[lower] = 1 - t;
    weights[upper] = t;
  }

  if (slots.length < itemCount) {
    return (pillRect: null, weights: weights);
  }
  final lowerRect = pillInset.deflateRect(slots[lower]);
  final rect = lower == upper
      ? lowerRect
      : Rect.lerp(lowerRect, pillInset.deflateRect(slots[upper]), t);
  return (pillRect: rect, weights: weights);
}

/// 比较两组槽位矩形是否完全一致。
bool sameSlotRects(List<Rect> a, List<Rect> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 离散选中下标对应的各槽位权重（选中项 1、其余 0）。
List<double> targetSlotWeights(int itemCount, int? selectedIndex) {
  final weights = List<double>.filled(itemCount, 0);
  if (selectedIndex != null &&
      selectedIndex >= 0 &&
      selectedIndex < itemCount) {
    weights[selectedIndex] = 1;
  }
  return weights;
}

/// 在起止权重间按进度 [t] 插值，并钳位到 `[0, 1]`。
List<double> lerpSlotWeights(
  List<double> from,
  List<double> to,
  int itemCount,
  double t,
  int? fallbackSelected,
) {
  if (from.length != itemCount || to.length != itemCount) {
    return targetSlotWeights(itemCount, fallbackSelected);
  }
  return <double>[
    for (var i = 0; i < itemCount; i++)
      (from[i] + (to[i] - from[i]) * t).clamp(0.0, 1.0),
  ];
}
