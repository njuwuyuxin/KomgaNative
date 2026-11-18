/// 翻页动画的几何：折线位置、倾角、半径、跟手进度、松手判定。
///
/// 全部是纯数值，不碰 Flutter——一是为了能在 VM 里毫秒级单测，
/// 二是倾角/节奏这类"手感参数"必须集中在一处，调的时候只改这里。
///
/// 坐标系：页面矩形左上角为原点，y 向下。
/// 标准形（`mirrored == false`）对应"书脊在右边、从**左下角**掀起"：
/// 折线起点在左下角，倾角 [kCurlTilt]；越翻倾角越小，最后贴着右边（书脊）变成竖直线。
library;

import 'dart:math' as math;

/// 起手时折线相对竖直方向的倾角（弧度）：≈31°，看起来是"捏住左下角掀起来"。
const double kCurlTilt = 0.55;

/// 圆柱半径 / 页宽。
const double kCurlRadiusRatio = 0.085;

/// 折线倾角随进度的衰减指数：>1 表示前段一直斜、临近书脊才迅速立直。
const double kCurlTiltDecay = 1.8;

/// 折线位置随进度的推进曲线。
///
/// 用 smoothstep（慢—快—慢）：起手像"先掀起一个角"，中段扫过页面，
/// 贴到书脊前收住。纯线性会显得呆板（而且收尾会"啪"一下撞上去）。
double curlPositionEase(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return p * p * (3 - 2 * p);
}

/// 折线倾角（弧度，恒为非负；方向由 [CurlGeometry.mirrored] 决定）。
double curlTiltAt(double progress) {
  final p = progress.clamp(0.0, 1.0);
  return kCurlTilt * math.pow(1 - p, kCurlTiltDecay).toDouble();
}

/// 一次翻页的折线几何（屏幕坐标，单位与页面矩形一致）。
class CurlGeometry {
  const CurlGeometry({
    required this.foldX,
    required this.foldY,
    required this.tilt,
    required this.radius,
    required this.width,
    required this.height,
    required this.progress,
    required this.mirrored,
  });

  /// 折线经过的一个点。
  final double foldX;
  final double foldY;

  /// 折线与竖直方向的夹角（弧度，非负）。
  final double tilt;

  /// 圆柱半径（px）。
  final double radius;

  final double width;
  final double height;

  /// 0 = 完全没翻，1 = 整页翻走。
  final double progress;

  /// true = 左右镜像（LTR 的书脊在左边）。
  final bool mirrored;

  /// 折线法线（指向"还没翻走"的那一侧）的 x 分量。
  ///
  /// 着色器就是用它把屏幕坐标投影到折线法线上：`s = (x-foldX)*nx + (y-foldY)*ny`，
  /// `s > 0` 处仍是平的纸面，`s < 0` 表示已经卷过去（露出下层）。
  double get normalX => mirrored ? -math.cos(tilt) : math.cos(tilt);

  /// 折线法线的 y 分量（始终向下偏）。
  double get normalY => math.sin(tilt);

  /// 进度为 0 时折线是否穿过"被捏住的角"（左下角 / 镜像时右下角）。
  ///
  /// 单测用它保证"起手一定从角上开始"，而不是整条边一起抬。
  bool get startsAtCorner {
    final cornerX = mirrored ? width : 0.0;
    final distance = (cornerX - foldX) * normalX + (height - foldY) * normalY;
    return distance.abs() < 1e-6;
  }
}

/// 计算某一帧的折线几何。
///
/// [progress] 是跟手进度（0..1）。折线点沿底边从左（镜像时从右）扫到书脊，
/// 倾角按 [curlTiltAt] 衰减；进度到 1 时折线与书脊重合、倾角为 0。
CurlGeometry curlGeometry({
  required double progress,
  required double width,
  required double height,
  bool mirrored = false,
  double radiusRatio = kCurlRadiusRatio,
}) {
  final p = progress.clamp(0.0, 1.0);
  final tilt = curlTiltAt(p);
  final along = curlPositionEase(p) * width;
  return CurlGeometry(
    foldX: mirrored ? width - along : along,
    foldY: height,
    tilt: tilt,
    radius: math.max(1.0, width * radiusRatio),
    width: width,
    height: height,
    progress: p,
    mirrored: mirrored,
  );
}

/// 横向拖动距离 → 跟手进度（0..1）。
///
/// [dx] 是手指相对按下位置的横向位移，[forwardSign] 是"往哪个方向拖算下一页"：
/// RTL 下往右拖（dx > 0）是下一页，所以传 +1；LTR 传 -1。
double turnProgressFromDrag({
  required double dx,
  required double width,
  required int forwardSign,
}) {
  if (width <= 0) return 0;
  final forward = dx * forwardSign;
  if (forward <= 0) return 0;
  return (forward / width).clamp(0.0, 1.0);
}

/// 松手后的补完时长（毫秒）。
///
/// 剩余距离越短补得越快，但有下限：太快的"啪一下"比不补完还难看。
const int kMinSettleMs = 120;

/// 松手判定 + 补完时长。
({bool commit, Duration duration}) settlePageTurn({
  required double progress,
  required double velocityX,
  required Duration base,
  int forwardSign = 1,
  double commitThreshold = 0.35,
  double flingVelocity = 350,
}) {
  final forwardVelocity = velocityX * forwardSign;
  final fling = forwardVelocity >= flingVelocity;
  // 已经拖过大半就顺势翻过去；只轻轻划一下（但够快）也算翻页。
  final commit = progress >= commitThreshold || fling && progress > 0.08;
  final remaining = commit ? 1 - progress : progress;
  final ms = (base.inMilliseconds * remaining).round();
  return (
    commit: commit,
    duration: Duration(milliseconds: math.max(kMinSettleMs, ms)),
  );
}
