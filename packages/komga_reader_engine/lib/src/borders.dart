import 'dart:typed_data';

/// 页图四周要裁掉的比例（0–1）。
///
/// 用比例而不是像素：解码时页图已经被降采样，比例才对不同分辨率一致。
class BorderCrop {
  const BorderCrop({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  static const BorderCrop none = BorderCrop(
    left: 0,
    top: 0,
    right: 0,
    bottom: 0,
  );

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isEmpty => left == 0 && top == 0 && right == 0 && bottom == 0;

  double get width => (1 - left - right).clamp(0.0, 1.0);
  double get height => (1 - top - bottom).clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is BorderCrop &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'BorderCrop(l: $left, t: $top, r: $right, b: $bottom)';
}

/// 检测页图四周的纯色边框（UI-P3-10 "去白边"）。
///
/// 算法：
/// 1. 取四角颜色，若四角差异过大（封面图铺满整页）直接认为没有边框；
/// 2. 从每条边向内扫，连续"至少 98% 像素接近背景色"的行/列算边框；
/// 3. 单边最多裁 40%，且四条边加起来不能把整页裁空。
///
/// 只在解码后的低分辨率 RGBA 上跑（32–64px 宽），成本 O(宽×高)。
BorderCrop? detectBorderCrop({
  required Uint8List rgba,
  required int width,
  required int height,
  int tolerance = 32,
  double maxFraction = 0.4,
}) {
  if (width <= 0 || height <= 0) return null;
  if (rgba.length < width * height * 4) return null;
  if (maxFraction <= 0 || maxFraction >= 0.5) return null;

  ({int r, int g, int b}) at(int x, int y) {
    final offset = (y * width + x) * 4;
    return (r: rgba[offset], g: rgba[offset + 1], b: rgba[offset + 2]);
  }

  final corners = <({int r, int g, int b})>[
    at(0, 0),
    at(width - 1, 0),
    at(0, height - 1),
    at(width - 1, height - 1),
  ];
  final bgR = corners.map((c) => c.r).reduce((a, b) => a + b) ~/ 4;
  final bgG = corners.map((c) => c.g).reduce((a, b) => a + b) ~/ 4;
  final bgB = corners.map((c) => c.b).reduce((a, b) => a + b) ~/ 4;
  for (final c in corners) {
    if ((c.r - bgR).abs() > tolerance ||
        (c.g - bgG).abs() > tolerance ||
        (c.b - bgB).abs() > tolerance) {
      return BorderCrop.none;
    }
  }

  bool matches(int x, int y) {
    final p = at(x, y);
    return (p.r - bgR).abs() <= tolerance &&
        (p.g - bgG).abs() <= tolerance &&
        (p.b - bgB).abs() <= tolerance;
  }

  final maxY = (height * maxFraction).floor().clamp(1, height ~/ 2);
  final maxX = (width * maxFraction).floor().clamp(1, width ~/ 2);
  final rowThreshold = (width * 98) ~/ 100;
  final colThreshold = (height * 98) ~/ 100;

  var top = 0;
  while (top < maxY) {
    var count = 0;
    for (var x = 0; x < width; x++) {
      if (matches(x, top)) count++;
    }
    if (count < rowThreshold) break;
    top++;
  }

  var bottom = 0;
  while (bottom < maxY) {
    final y = height - 1 - bottom;
    var count = 0;
    for (var x = 0; x < width; x++) {
      if (matches(x, y)) count++;
    }
    if (count < rowThreshold) break;
    bottom++;
  }

  var left = 0;
  while (left < maxX) {
    var count = 0;
    for (var y = 0; y < height; y++) {
      if (matches(left, y)) count++;
    }
    if (count < colThreshold) break;
    left++;
  }

  var right = 0;
  while (right < maxX) {
    final x = width - 1 - right;
    var count = 0;
    for (var y = 0; y < height; y++) {
      if (matches(x, y)) count++;
    }
    if (count < colThreshold) break;
    right++;
  }

  // 整页都是背景色：不裁（否则会得到 0×0，阅读器闪黑）。
  final horizontal = (left + right) / width;
  final vertical = (top + bottom) / height;
  if (horizontal >= 0.8 || vertical >= 0.8) return BorderCrop.none;

  if (top == 0 && bottom == 0 && left == 0 && right == 0) {
    return BorderCrop.none;
  }
  return BorderCrop(
    left: left / width,
    top: top / height,
    right: right / width,
    bottom: bottom / height,
  );
}
