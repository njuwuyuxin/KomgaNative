/// 卷页的"手指运动"：拖动、点击自动翻页、松手补完——都归结为一条手指轨迹。
///
/// 几何（手指 → 圆柱）见 `page_turn.dart`；这里只回答"这一帧手指在哪"。
/// 所有坐标都是**标准形**（角在左下 `(0, height)`、书脊在右），镜像由
/// [solveCurl] 的 `mirrored` 处理。
library;

import 'package:yomu_reader/src/page_turn.dart';

/// 一次卷页翻动的轨迹。
///
/// - 往前翻：当前页从角上卷起，`turn = 0` 平铺、`turn = 1` 翻走；
/// - 往回翻：上一页从书脊外**卷回来**，正好是往前翻的倒放，
///   所以路径进度是 `1 − turn`——两者在任何进度上都严格对称。
class CurlMotion {
  const CurlMotion({
    required this.forward,
    required this.width,
    required this.height,
    required this.exitX,
    this.hinged = false,
    this.radiusRatio = kCurlRadiusRatio,
  });

  /// true = 往前翻（卷走当前页），false = 往回翻（卷回上一页）。
  final bool forward;

  /// 被卷那张纸的尺寸。
  final double width;
  final double height;

  /// 从被捏住的角那条边量到屏幕另一侧边缘的距离，见 [curlTravel]。
  final double exitX;

  /// true = 双页：纸铰接在书脊上，翻过去平落在另一半页（见 `page_turn.dart`）。
  final bool hinged;

  final double radiusRatio;

  /// 翻页进度 → 路径进度（往回翻是倒放）。
  double pathProgress(double turn) => forward ? turn : 1 - turn;

  /// 自动翻页时，翻页进度 [turn] 对应的手指位置（带拱起）。
  ({double x, double y}) fingerAt(double turn) => curlFingerAt(
    progress: pathProgress(turn),
    width: width,
    height: height,
    exitX: exitX,
    hinged: hinged,
    radiusRatio: radiusRatio,
  );

  /// 整段路径的长度（手指要走多远纸才完全翻走）。
  double get travel => curlTravel(
    width: width,
    exitX: exitX,
    hinged: hinged,
    radiusRatio: radiusRatio,
  );

  /// 跟手：手指相对按下点的位移（[along] 为朝翻页方向的横向距离，[dy] 纵向）。
  ///
  /// 往前翻时角**就在手指下面**：位移直接加在角上，往上拖折线自然变斜。
  /// 往回翻时上一页的角远在屏幕外，从路径终点往回退同样的距离——
  /// 于是两个方向的折线都以手指速度的一半移动，手感对称。
  ({double x, double y}) dragFinger({
    required double along,
    required double dy,
  }) {
    final a = along.clamp(0.0, travel);
    return (x: forward ? a : travel - a, y: height + dy);
  }

  /// 手指位置对应的翻页进度（0..1），用来接续补完动画。
  double turnOf(({double x, double y}) finger) {
    final t = travel <= 0 ? 0.0 : (finger.x / travel).clamp(0.0, 1.0);
    return forward ? t : 1 - t;
  }

  /// 补完动画第 [t]（0..1，已过缓动）帧的手指位置。
  ///
  /// 从松手时的手指 [from]（翻页进度 [fromTurn]）走到 [toTurn] 的路径点：
  /// 两端之间是直线，再叠上"路径相对自身弦的偏离"——于是点击翻页时
  /// （起点正好在路径上）完全沿拱形路径走，拖到一半松手也不会跳。
  ({double x, double y}) settleFinger({
    required ({double x, double y}) from,
    required double fromTurn,
    required double toTurn,
    required double t,
  }) {
    final k = t.clamp(0.0, 1.0);
    final to = fingerAt(toTurn);
    final p0 = fingerAt(fromTurn);
    final pk = fingerAt(fromTurn + (toTurn - fromTurn) * k);
    // 路径在 [fromTurn, toTurn] 上相对弦的偏离（拱起部分）。
    final bulgeX = pk.x - (p0.x + (to.x - p0.x) * k);
    final bulgeY = pk.y - (p0.y + (to.y - p0.y) * k);
    return (
      x: from.x + (to.x - from.x) * k + bulgeX,
      y: from.y + (to.y - from.y) * k + bulgeY,
    );
  }

  /// 某个手指位置下的卷页几何。
  CurlFrame frame(({double x, double y}) finger, {required bool mirrored}) =>
      solveCurl(
        fingerX: finger.x,
        fingerY: finger.y,
        width: width,
        height: height,
        mirrored: mirrored,
        hinged: hinged,
        radiusRatio: radiusRatio,
      );
}
