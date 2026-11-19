import 'dart:typed_data';

/// 一个 8 位 RGB 颜色。
///
/// 引擎是纯 Dart，不能依赖 `dart:ui` 的 `Color`；Widget 层负责转成 `Color`。
class RgbColor {
  const RgbColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;

  /// 感知亮度（0–255，整数运算，不引入浮点）。
  int get luminance => (r * 299 + g * 587 + b * 114) ~/ 1000;

  bool get isDark => luminance < 128;

  @override
  bool operator ==(Object other) =>
      other is RgbColor && other.r == r && other.g == g && other.b == b;

  @override
  int get hashCode => Object.hash(r, g, b);

  @override
  String toString() => 'RgbColor($r, $g, $b)';
}

/// 取"页边主色"（UI-P1-5 动态背景）。
///
/// 只统计四边 [band] 像素宽的边框：漫画正文在中间，页边才代表"这一页的底色"，
/// 拿整页平均会被大面积的黑／白框线或者对话框拉偏。
///
/// 容错（都有单测）：
/// - 完全透明的像素跳过（带 alpha 的 PNG、还没解码完的缓冲）；
/// - 图比边框还小（1×1）时退化成整图平均，而不是返回空；
/// - 空图 / 全透明 / 尺寸不合法返回 null，调用方回退到默认背景，不要黑屏。
///
/// 复杂度 O(周长 × band)：32×48 的降采样图大约一千像素，可以放在 UI 线程上跑
/// （真正贵的图像解码由 Flutter 引擎在后台线程完成）。
RgbColor? edgeColor({
  required Uint8List rgba,
  required int width,
  required int height,
  int band = 2,
}) {
  if (width <= 0 || height <= 0) return null;
  if (rgba.length < width * height * 4) return null;

  final shortest = width < height ? width : height;
  final half = shortest ~/ 2;
  // 半边长可能是 0（1×1 图）：下限仍取 1，让整图象都算在"页边"里。
  final maxBand = half < 1 ? 1 : half;
  final inset = band.clamp(1, maxBand);
  var sumR = 0;
  var sumG = 0;
  var sumB = 0;
  var count = 0;

  void sample(int x, int y) {
    final offset = (y * width + x) * 4;
    final alpha = rgba[offset + 3];
    if (alpha == 0) return;
    sumR += rgba[offset];
    sumG += rgba[offset + 1];
    sumB += rgba[offset + 2];
    count++;
  }

  for (var y = 0; y < height; y++) {
    final inBandY = y < inset || y >= height - inset;
    if (inBandY) {
      // 整行都在边框带里：左右两段都要算（小图时就是整行）。
      for (var x = 0; x < width; x++) {
        sample(x, y);
      }
      continue;
    }
    for (var x = 0; x < width; x++) {
      if (x < inset || x >= width - inset) sample(x, y);
    }
  }

  if (count == 0) return null;
  return RgbColor(sumR ~/ count, sumG ~/ count, sumB ~/ count);
}

/// 左右两侧页边的主色（UI-P3-7 沉浸式动态背景）。
///
/// 返回顺序是 `[左, 右]`（某侧没有可用像素就省略）；颜色算法与 [edgeColor]
/// 同样只统计边框带、跳过透明像素。Widget 层用它做双色渐变。
List<RgbColor> edgeColors({
  required Uint8List rgba,
  required int width,
  required int height,
  int band = 2,
}) {
  if (width <= 0 || height <= 0) return const <RgbColor>[];
  if (rgba.length < width * height * 4) return const <RgbColor>[];

  final shortest = width < height ? width : height;
  final half = shortest ~/ 2;
  final maxBand = half < 1 ? 1 : half;
  final inset = band.clamp(1, maxBand);

  var leftR = 0, leftG = 0, leftB = 0, leftCount = 0;
  var rightR = 0, rightG = 0, rightB = 0, rightCount = 0;

  void sample(int x, int y, {required bool left}) {
    final offset = (y * width + x) * 4;
    if (rgba[offset + 3] == 0) return;
    if (left) {
      leftR += rgba[offset];
      leftG += rgba[offset + 1];
      leftB += rgba[offset + 2];
      leftCount++;
    } else {
      rightR += rgba[offset];
      rightG += rgba[offset + 1];
      rightB += rgba[offset + 2];
      rightCount++;
    }
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < inset; x++) {
      sample(x, y, left: true);
    }
    for (var x = width - inset; x < width; x++) {
      if (x >= 0) sample(x, y, left: false);
    }
  }

  return <RgbColor>[
    if (leftCount > 0)
      RgbColor(leftR ~/ leftCount, leftG ~/ leftCount, leftB ~/ leftCount),
    if (rightCount > 0)
      RgbColor(
        rightR ~/ rightCount,
        rightG ~/ rightCount,
        rightB ~/ rightCount,
      ),
  ];
}

/// 一屏里多页（双页跨页）的页边色取平均；全为空时返回 null。
///
/// 不做"哪一页占主导"的判定：跨页时两页的底色本来就该融合，
/// 取平均在视觉上最接近"纸的底色"。
RgbColor? averageColors(List<RgbColor?> colors) {
  var count = 0;
  var sumR = 0;
  var sumG = 0;
  var sumB = 0;
  for (final color in colors) {
    if (color == null) continue;
    sumR += color.r;
    sumG += color.g;
    sumB += color.b;
    count++;
  }
  if (count == 0) return null;
  return RgbColor(sumR ~/ count, sumG ~/ count, sumB ~/ count);
}
