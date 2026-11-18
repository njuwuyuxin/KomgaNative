/// 翻页动画的几何：圆柱卷页模型 + 手指路径 + 松手判定。
///
/// 全部是纯数值，不碰 Flutter——一是为了能在 VM 里毫秒级单测，
/// 二是手感参数必须集中在一处，调的时候只改这里。
///
/// ## 模型
///
/// 纸被"捏住的角" `C` 拖到手指 `F`，纸沿一根半径 `R` 的圆柱卷过去：
///
/// ```text
///          ┌──────────── 卷过去平压的部分（背面朝上，高度 2R）
///         ╭╯
///        (   圆柱：下半圈是正面，上半圈是背面
///         ╰╮
/// ─────────┘ 还平铺在原位的部分（正面）        u →（指向被捏住的角）
///          ↑ 圆柱轴线 A
/// ```
///
/// - 卷曲方向 `u = normalize(C − F)`，轴线垂直于 `u`；
/// - 角到轴线的纸长 `a` 满足"卷过半圈后平压下来正好落在手指上"：
///   `|F − C| = 2a − πR`，所以 `a = (|F − C| + πR) / 2`，轴线点 `A = C − u·a`；
/// - 屏幕点 `p` 到轴线的有符号距离 `d = (p − A)·u` 决定它看到哪一层，
///   逆映射见 `apps/app/shaders/page_curl.frag`。
///
/// 折线倾角不再是拍脑袋的参数：手指往上走折线就斜，水平拖折线就竖——
/// 由 `F` 的位置唯一决定。
///
/// 坐标系：纸面矩形左上角为原点，y 向下。
/// 标准形（`mirrored == false`）对应"书脊在右边、从**左下角**掀起"；
/// 镜像形是左右翻转（书脊在左边、从右下角掀起）。
library;

import 'dart:math' as math;

/// 卷筒最大半径 / 页宽。
const double kCurlRadiusRatio = 0.085;

/// 自动翻页路径的"拱起"高度 / 页宽。
///
/// 手指沿一条往上拱的弧线走，折线才是参考效果那种斜着掀起的样子；
/// 纯水平路径折线始终竖直，像一扇门而不是一张纸。
const double kCurlArchRatio = 0.28;

/// `u` 相对水平方向的最大倾角（弧度，≈52°）。
///
/// 再斜下去，卷起的就不是"一个角"而是整条左边，看起来像撕纸。
const double kCurlMaxTilt = 0.9;

/// 角离起点不到这个距离（px）时视为完全平铺。
const double _flatEpsilon = 1e-3;

/// 卷筒半径随"角被拖开的距离" [reach] 变化。
///
/// 起手半径必须趋于 0：否则 `a = πR/2 > 0`，手指还没动角就已经卷起来了（跳变）。
/// 用 `t(2 − t)` 在 `reach = 4R_max` 处平滑饱和（斜率连续为 0），全程无折点。
double curlRadiusFor(double reach, double maxRadius) {
  if (maxRadius <= 0 || reach <= 0) return 0;
  final t = math.min(1.0, reach / (4 * maxRadius));
  return maxRadius * t * (2 - t);
}

/// 某一帧的卷页几何（纸面坐标，单位与纸面矩形一致）。
class CurlFrame {
  const CurlFrame({
    required this.axisX,
    required this.axisY,
    required this.dirX,
    required this.dirY,
    required this.radius,
    required this.fingerX,
    required this.fingerY,
    required this.width,
    required this.height,
    required this.mirrored,
  });

  /// 圆柱轴线（在纸面上的投影）经过的点。
  final double axisX;
  final double axisY;

  /// 单位向量 `u`：从轴线指向被卷起的一侧（被捏住的角那边）。
  final double dirX;
  final double dirY;

  /// 圆柱半径（px）。0 表示还没卷（或卷成了一道折痕）。
  final double radius;

  /// 被捏住的角当前落在哪里（也就是手指位置，约束之后）。
  final double fingerX;
  final double fingerY;

  final double width;
  final double height;

  /// true = 左右镜像（书脊在左边）。
  final bool mirrored;

  /// 被捏住的角在纸面上的原始位置。
  double get cornerX => mirrored ? width : 0;
  double get cornerY => height;

  /// 纸面点 `(x, y)` 到轴线的有符号距离：> 0 已卷起，<= 0 还平铺在原位。
  double signedDistance(double x, double y) =>
      (x - axisX) * dirX + (y - axisY) * dirY;

  /// 纸面点 `(x, y)` 是否还平铺在原位（没被卷走）。
  bool isFlatAt(double x, double y) => signedDistance(x, y) <= 0;
}

/// 把手指位置 `F` 约束到合理范围（标准形坐标）。
///
/// - 手指不能低于底边（否则 `u` 朝上，卷起的是整个上半页）；
/// - `u` 的倾角不超过 [kCurlMaxTilt]。
({double x, double y}) constrainFinger({
  required double fingerX,
  required double fingerY,
  required double height,
}) {
  var vx = fingerX;
  var vy = math.min(0.0, fingerY - height);
  final length = math.sqrt(vx * vx + vy * vy);
  if (length <= _flatEpsilon) return (x: 0, y: height);
  final tilt = math.atan2(-vy, vx);
  if (tilt > kCurlMaxTilt) {
    vx = length * math.cos(kCurlMaxTilt);
    vy = -length * math.sin(kCurlMaxTilt);
  }
  return (x: vx, y: height + vy);
}

/// 由手指位置解出卷页几何。
///
/// [fingerX]/[fingerY] 是**标准形**坐标（角在左下 `(0, height)`）；
/// [mirrored] 只影响输出：在标准形里算完再左右翻转。
CurlFrame solveCurl({
  required double fingerX,
  required double fingerY,
  required double width,
  required double height,
  bool mirrored = false,
  double radiusRatio = kCurlRadiusRatio,
}) {
  final f = constrainFinger(fingerX: fingerX, fingerY: fingerY, height: height);
  final vx = f.x;
  final vy = f.y - height;
  final reach = math.sqrt(vx * vx + vy * vy);

  double ux;
  double uy;
  double radius;
  double a;
  if (reach <= _flatEpsilon) {
    // 还没拖开：轴线就压在角上，卷起部分为空。
    ux = -1;
    uy = 0;
    radius = 0;
    a = 0;
  } else {
    ux = -vx / reach;
    uy = -vy / reach;
    radius = curlRadiusFor(reach, width * radiusRatio);
    a = (reach + math.pi * radius) / 2;
  }
  final axisX = 0 - ux * a;
  final axisY = height - uy * a;

  return CurlFrame(
    axisX: mirrored ? width - axisX : axisX,
    axisY: axisY,
    dirX: mirrored ? -ux : ux,
    dirY: uy,
    radius: radius,
    fingerX: mirrored ? width - f.x : f.x,
    fingerY: f.y,
    width: width,
    height: height,
    mirrored: mirrored,
  );
}

/// 手指要走多远（`|F − C|`），整张纸连同卷筒才完全越过 [exitX]。
///
/// [exitX] 是从被捏住的角那条边量到"屏幕另一侧边缘"的距离（≥ 页宽）：
/// 卷筒必须滑出**屏幕**，而不是只滑出纸面——否则页面窄于屏幕时，
/// 收尾会剩一根白柱停在空白处凭空消失。
double curlTravel({
  required double width,
  required double exitX,
  double radiusRatio = kCurlRadiusRatio,
}) {
  final maxRadius = width * radiusRatio;
  // 走完时半径已饱和（travel ≫ 4R_max），所以直接用 R_max 反解：
  // 轴线要到 exitX + R，于是 a = exitX + R，|F − C| = 2a − πR。
  final a = math.max(exitX, width) + maxRadius;
  return 2 * a - math.pi * maxRadius + 1;
}

/// 自动翻页 / 跟手翻页共用的手指路径（标准形坐标）。
///
/// [progress] 0 = 纸平铺，1 = 纸完全翻走。路径沿底边向书脊推进，
/// 中途往上拱起 [kCurlArchRatio]·页宽，于是折线先斜后竖；
/// [liftY] 是跟手时手指的纵向位移（向上为负），叠加在路径上。
({double x, double y}) curlFingerAt({
  required double progress,
  required double width,
  required double height,
  required double exitX,
  double liftY = 0,
  double radiusRatio = kCurlRadiusRatio,
}) {
  final p = progress.clamp(0.0, 1.0);
  final travel = curlTravel(
    width: width,
    exitX: exitX,
    radiusRatio: radiusRatio,
  );
  final arch = width * kCurlArchRatio * math.sin(math.pi * p);
  return (x: travel * p, y: height - arch + liftY);
}

/// 一步到位：按路径进度算出一帧几何。
CurlFrame curlFrameAt({
  required double progress,
  required double width,
  required double height,
  required double exitX,
  double liftY = 0,
  bool mirrored = false,
  double radiusRatio = kCurlRadiusRatio,
}) {
  final f = curlFingerAt(
    progress: progress,
    width: width,
    height: height,
    exitX: exitX,
    liftY: liftY,
    radiusRatio: radiusRatio,
  );
  return solveCurl(
    fingerX: f.x,
    fingerY: f.y,
    width: width,
    height: height,
    mirrored: mirrored,
    radiusRatio: radiusRatio,
  );
}

/// 横向拖动距离 → 跟手进度（0..1）。
///
/// [dx] 是手指相对按下位置的横向位移，[forwardSign] 是"往哪个方向拖算这次翻页"：
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
