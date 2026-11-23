import 'dart:math' as math;

import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:test/test.dart';

/// 圆柱卷页的几何与手指运动。
///
/// 核心不变量：被捏住的角绕圆柱卷过半圈后，正好落在手指下面。
void main() {
  const width = 1000.0;
  const height = 1500.0;
  const exitX = 1000.0;

  /// 把纸面点 q 按卷页模型映射到屏幕（只处理"翻过去平压"那一段）。
  ({double x, double y}) flippedScreen(CurlFrame f, double qx, double qy) {
    final s = f.signedDistance(qx, qy);
    final r = f.radius;
    // 弧长 s >= πR：屏幕上 d = πR − s，沿 u 方向的位移是 (d − s)。
    final shift = (math.pi * r - s) - s;
    return (x: qx + f.dirX * shift, y: qy + f.dirY * shift);
  }

  group('solveCurl', () {
    test('手指在角上：完全平铺，整张纸都还在原位', () {
      final f = solveCurl(
        fingerX: 0,
        fingerY: height,
        width: width,
        height: height,
      );
      expect(f.radius, 0);
      expect(f.isFlatAt(0, height), isTrue);
      expect(f.isFlatAt(width, 0), isTrue);
    });

    test('卷过半圈后，角正好落在手指下面（几何闭式解）', () {
      for (final finger in <(double, double)>[
        (300, height),
        (500, height - 400),
        (1600, height - 200),
        (40, height - 10),
      ]) {
        final f = solveCurl(
          fingerX: finger.$1,
          fingerY: finger.$2,
          width: width,
          height: height,
        );
        final landed = flippedScreen(f, 0, height);
        expect(landed.x, closeTo(f.fingerX, 1e-6), reason: '$finger');
        expect(landed.y, closeTo(f.fingerY, 1e-6), reason: '$finger');
      }
    });

    test('起手只掀起左下角：左上角、右下角都还平铺', () {
      final f = solveCurl(
        fingerX: 120,
        fingerY: height - 60,
        width: width,
        height: height,
      );
      expect(f.isFlatAt(0, height), isFalse, reason: '被捏住的角已经卷起');
      expect(f.isFlatAt(0, 0), isTrue);
      expect(f.isFlatAt(width, height), isTrue);
      expect(f.isFlatAt(width, 0), isTrue);
    });

    test('半径随拖开距离连续增长：起手趋于 0，之后饱和在最大值', () {
      expect(curlRadiusFor(0, 85), 0);
      expect(curlRadiusFor(1, 85), lessThan(1));
      var previous = 0.0;
      for (var reach = 0.0; reach <= 2000; reach += 10) {
        final r = curlRadiusFor(reach, 85);
        expect(r, greaterThanOrEqualTo(previous - 1e-9));
        expect(r, lessThanOrEqualTo(85 + 1e-9));
        previous = r;
      }
      expect(curlRadiusFor(2000, 85), closeTo(85, 1e-9));
    });

    test('往上拖：折线变斜（u 有向下的分量，左下角先卷）', () {
      final level = solveCurl(
        fingerX: 400,
        fingerY: height,
        width: width,
        height: height,
      );
      expect(level.dirX, closeTo(-1, 1e-9));
      expect(level.dirY, closeTo(0, 1e-9), reason: '水平拖：折线竖直');

      final raised = solveCurl(
        fingerX: 400,
        fingerY: height - 300,
        width: width,
        height: height,
      );
      expect(raised.dirX, lessThan(0));
      expect(raised.dirY, greaterThan(0), reason: '往上拖：u 指向左下角');
    });

    test('手指低于底边：按底边处理，不会把上半页卷起来', () {
      final f = solveCurl(
        fingerX: 300,
        fingerY: height + 500,
        width: width,
        height: height,
      );
      expect(f.fingerY, height);
      expect(f.dirY, closeTo(0, 1e-9));
    });

    test('倾角有上限：几乎竖直往上拖也不会卷起整条左边', () {
      final f = solveCurl(
        fingerX: 1,
        fingerY: height - 800,
        width: width,
        height: height,
      );
      final tilt = math.atan2(f.dirY, -f.dirX);
      expect(tilt, lessThanOrEqualTo(kCurlMaxTilt + 1e-9));
    });

    test('镜像（书脊在左）：从右下角掀起，几何左右对称', () {
      final standard = solveCurl(
        fingerX: 350,
        fingerY: height - 200,
        width: width,
        height: height,
      );
      final mirrored = solveCurl(
        fingerX: 350,
        fingerY: height - 200,
        width: width,
        height: height,
        mirrored: true,
      );
      expect(mirrored.cornerX, width);
      expect(mirrored.axisX, closeTo(width - standard.axisX, 1e-9));
      expect(mirrored.axisY, closeTo(standard.axisY, 1e-9));
      expect(mirrored.dirX, closeTo(-standard.dirX, 1e-9));
      expect(mirrored.dirY, closeTo(standard.dirY, 1e-9));
      expect(mirrored.radius, standard.radius);
      expect(mirrored.isFlatAt(width, height), isFalse);
      expect(mirrored.isFlatAt(0, height), isTrue);
    });

    test('窄页、零尺寸：不出 NaN', () {
      final f = solveCurl(fingerX: 5, fingerY: 5, width: 0, height: 10);
      expect(f.axisX.isNaN, isFalse);
      expect(f.radius.isNaN, isFalse);
    });
  });

  group('curlFrameAt（自动翻页路径）', () {
    test('进度 0：完全平铺', () {
      final f = curlFrameAt(
        progress: 0,
        width: width,
        height: height,
        exitX: exitX,
      );
      expect(f.radius, 0);
      expect(f.isFlatAt(0, height), isTrue);
    });

    test('进度 1：整张纸连同卷筒都滑出了屏幕另一侧', () {
      final f = curlFrameAt(
        progress: 1,
        width: width,
        height: height,
        exitX: exitX,
      );
      for (final c in <(double, double)>[
        (0, 0),
        (width, 0),
        (0, height),
        (width, height),
      ]) {
        expect(f.isFlatAt(c.$1, c.$2), isFalse, reason: '角 $c 不该还平铺');
      }
      // 圆柱在屏幕上占 d ∈ [0, R]，最靠近书脊的一侧是轴线左边 R 处。
      expect(f.axisX - f.radius, greaterThanOrEqualTo(exitX));
    });

    test('页面窄于屏幕时，卷筒要滑出屏幕而不是只滑出纸面', () {
      final f = curlFrameAt(
        progress: 1,
        width: width,
        height: height,
        exitX: 1600,
      );
      expect(f.axisX - f.radius, greaterThanOrEqualTo(1600));
    });

    test('中途往上拱：折线是斜的（参考效果那种斜卷）', () {
      final f = curlFrameAt(
        progress: 0.4,
        width: width,
        height: height,
        exitX: exitX,
      );
      expect(f.dirY, greaterThan(0.2));
    });

    test('轴线随进度单调向书脊推进（不倒退、不跳变）', () {
      var previous = -double.infinity;
      var previousRadius = 0.0;
      for (var i = 0; i <= 100; i++) {
        final f = curlFrameAt(
          progress: i / 100,
          width: width,
          height: height,
          exitX: exitX,
        );
        // 用底边上轴线的位置衡量推进：(x − A)·u = 0 且 y = height。
        final bottomX = f.axisX - (height - f.axisY) * f.dirY / f.dirX;
        expect(bottomX, greaterThanOrEqualTo(previous - 1e-6), reason: '$i');
        if (i > 0) {
          expect(bottomX - previous, lessThan(width * 0.1), reason: '跳变 @$i');
        }
        expect(
          (f.radius - previousRadius).abs(),
          lessThan(width * 0.02),
          reason: '半径跳变 @$i',
        );
        previous = bottomX;
        previousRadius = f.radius;
      }
    });
  });

  group('双页：铰接在书脊上', () {
    const half = 700.0;
    const hinged = CurlMotion(
      forward: true,
      width: half,
      height: height,
      exitX: half,
      hinged: true,
    );

    /// 书脊两端（标准形 x = width）到轴线的有符号距离都不能为正。
    void expectSpineFlat(CurlFrame f, String reason) {
      final spineX = f.mirrored ? 0.0 : f.width;
      // 夹紧时轴线正好压在书脊端点上，允许浮点误差。
      expect(f.signedDistance(spineX, 0), lessThan(1e-6), reason: '上端 $reason');
      expect(
        f.signedDistance(spineX, f.height),
        lessThan(1e-6),
        reason: '下端 $reason',
      );
    }

    test('整段路径（含往上拖）轴线都不越过书脊', () {
      for (final lift in <double>[0, -200, -600]) {
        for (var i = 0; i <= 100; i++) {
          final finger = hinged.fingerAt(i / 100);
          final f = hinged.frame((
            x: finger.x,
            y: finger.y + lift,
          ), mirrored: false);
          expectSpineFlat(f, '@$i lift=$lift');
        }
      }
    });

    test('终点：半径收成 0，纸沿书脊镜像，角落在另一半页的对应角上', () {
      expect(hinged.travel, closeTo(2 * half, 1e-9));
      final f = hinged.frame(hinged.fingerAt(1), mirrored: false);
      expect(f.radius, closeTo(0, 1e-9));
      expect(f.axisX, closeTo(half, 1e-9));
      expect(f.dirX, closeTo(-1, 1e-9));
      expect(f.dirY, closeTo(0, 1e-9));
      final landed = flippedScreen(f, 0, height);
      expect(landed.x, closeTo(2 * half, 1e-6));
      expect(landed.y, closeTo(height, 1e-6));
    });

    test('前半段卷起、后半段落下：半径先增后减，全程连续', () {
      var peak = 0.0;
      var previous = 0.0;
      for (var i = 0; i <= 200; i++) {
        final f = hinged.frame(hinged.fingerAt(i / 200), mirrored: false);
        expect(
          (f.radius - previous).abs(),
          lessThan(half * 0.01),
          reason: '$i',
        );
        if (f.radius > peak) peak = f.radius;
        previous = f.radius;
      }
      expect(peak, greaterThan(half * kCurlRadiusRatio * 0.8));
    });

    test('镜像（LTR）：书脊在左，几何左右对称', () {
      final finger = hinged.fingerAt(0.6);
      final a = hinged.frame(finger, mirrored: false);
      final b = hinged.frame(finger, mirrored: true);
      expect(b.axisX, closeTo(half - a.axisX, 1e-9));
      expect(b.dirX, closeTo(-a.dirX, 1e-9));
      expect(b.radius, a.radius);
      expectSpineFlat(b, 'mirrored');
    });

    test('往回翻：起点纸已平落在另一半上（与当前屏一致），终点平铺', () {
      const back = CurlMotion(
        forward: false,
        width: half,
        height: height,
        exitX: half,
        hinged: true,
      );
      final start = back.frame(back.fingerAt(0), mirrored: false);
      expect(start.radius, closeTo(0, 1e-9));
      expect(start.axisX, closeTo(half, 1e-9));
      final end = back.frame(back.fingerAt(1), mirrored: false);
      expect(end.isFlatAt(0, height), isTrue);
    });

    test('拖过头：手指夹在终点，不会把纸从书脊上扯下来', () {
      final f = hinged.frame(
        hinged.dragFinger(along: 5000, dy: 0),
        mirrored: false,
      );
      expectSpineFlat(f, 'overdrag');
      expect(f.radius, closeTo(0, 1e-9));
    });

    test('临近落地时半径减速收敛且折线回正到书脊', () {
      final f95 = hinged.frame(hinged.fingerAt(0.95), mirrored: false);
      final f98 = hinged.frame(hinged.fingerAt(0.98), mirrored: false);
      final f100 = hinged.frame(hinged.fingerAt(1.0), mirrored: false);
      // smoothstep 收尾：越接近终点，半径收缩越平缓（不会末帧骤降）。
      expect(f98.radius - f100.radius, lessThan(f95.radius - f98.radius));
      // 临近翻完前折线已基本竖直贴合书脊。
      expect(f95.dirY.abs(), lessThan(0.02));
      expect(f98.dirY.abs(), lessThan(0.005));
    });
  });

  group('CurlMotion', () {
    const forward = CurlMotion(
      forward: true,
      width: width,
      height: height,
      exitX: exitX,
    );
    const backward = CurlMotion(
      forward: false,
      width: width,
      height: height,
      exitX: exitX,
    );

    test('往回翻是往前翻的倒放：任意进度下手指位置互为镜像时刻', () {
      for (var i = 0; i <= 10; i++) {
        final t = i / 10;
        final a = forward.fingerAt(t);
        final b = backward.fingerAt(1 - t);
        expect(b.x, closeTo(a.x, 1e-9));
        expect(b.y, closeTo(a.y, 1e-9));
      }
    });

    test('往回翻起点：纸完全在屏幕外；终点：完全平铺', () {
      final start = backward.frame(backward.fingerAt(0), mirrored: false);
      expect(start.isFlatAt(width, 0), isFalse);
      final end = backward.frame(backward.fingerAt(1), mirrored: false);
      expect(end.radius, 0);
      expect(end.isFlatAt(0, height), isTrue);
    });

    test('往前拖：角跟着手指走，往上拖就是往上', () {
      final f = forward.dragFinger(along: 300, dy: -120);
      expect(f.x, 300);
      expect(f.y, height - 120);
      expect(forward.dragFinger(along: -50, dy: 0).x, 0, reason: '反向拖不卷');
    });

    test('往回拖：从路径终点往回退，拖得越多盖得越多', () {
      final none = backward.dragFinger(along: 0, dy: 0);
      expect(none.x, closeTo(backward.travel, 1e-9));
      final some = backward.dragFinger(along: 400, dy: 0);
      expect(some.x, closeTo(backward.travel - 400, 1e-9));
      expect(backward.turnOf(some), greaterThan(backward.turnOf(none)));
    });

    test('turnOf 与 fingerAt 互逆（横向分量）', () {
      for (var i = 0; i <= 10; i++) {
        final t = i / 10;
        expect(forward.turnOf(forward.fingerAt(t)), closeTo(t, 1e-9));
        expect(backward.turnOf(backward.fingerAt(t)), closeTo(t, 1e-9));
      }
    });

    test('补完：t = 0 停在松手处，t = 1 到达目标，中途不跳', () {
      const from = (x: 700.0, y: height - 350.0);
      final fromTurn = forward.turnOf(from);
      final start = forward.settleFinger(
        from: from,
        fromTurn: fromTurn,
        toTurn: 1,
        t: 0,
      );
      expect(start.x, closeTo(from.x, 1e-9));
      expect(start.y, closeTo(from.y, 1e-9));
      final end = forward.settleFinger(
        from: from,
        fromTurn: fromTurn,
        toTurn: 1,
        t: 1,
      );
      final target = forward.fingerAt(1);
      expect(end.x, closeTo(target.x, 1e-9));
      expect(end.y, closeTo(target.y, 1e-9));

      var prev = start;
      for (var i = 1; i <= 50; i++) {
        final p = forward.settleFinger(
          from: from,
          fromTurn: fromTurn,
          toTurn: 1,
          t: i / 50,
        );
        final step = math.sqrt(
          math.pow(p.x - prev.x, 2) + math.pow(p.y - prev.y, 2),
        );
        expect(step, lessThan(forward.travel * 0.06), reason: '跳变 @$i');
        prev = p;
      }
    });

    test('点击翻页（起点在路径上）：补完完全沿拱形路径走', () {
      final from = forward.fingerAt(0);
      for (var i = 0; i <= 10; i++) {
        final t = i / 10;
        final p = forward.settleFinger(
          from: from,
          fromTurn: 0,
          toTurn: 1,
          t: t,
        );
        final onPath = forward.fingerAt(t);
        expect(p.x, closeTo(onPath.x, 1e-9));
        expect(p.y, closeTo(onPath.y, 1e-9));
      }
    });
  });

  group('turnProgressFromDrag', () {
    test('RTL：往右拖才是下一页，进度按拖动距离算', () {
      expect(
        turnProgressFromDrag(dx: 300, width: 1000, forwardSign: 1),
        closeTo(0.3, 1e-9),
      );
      expect(turnProgressFromDrag(dx: -300, width: 1000, forwardSign: 1), 0);
    });

    test('LTR：往左拖才是下一页', () {
      expect(
        turnProgressFromDrag(dx: -300, width: 1000, forwardSign: -1),
        closeTo(0.3, 1e-9),
      );
      expect(turnProgressFromDrag(dx: 300, width: 1000, forwardSign: -1), 0);
    });

    test('夹在 0..1 之间，宽度非法时不出 NaN', () {
      expect(turnProgressFromDrag(dx: 5000, width: 1000, forwardSign: 1), 1.0);
      expect(turnProgressFromDrag(dx: 100, width: 0, forwardSign: 1), 0);
    });
  });

  group('settlePageTurn', () {
    const base = Duration(milliseconds: 400);

    test('拖过阈值就翻过去，剩余距离决定补完时长', () {
      const slowBase = Duration(milliseconds: 1000);
      final r = settlePageTurn(progress: 0.5, velocityX: 0, base: slowBase);
      expect(r.commit, isTrue);
      expect(r.duration.inMilliseconds, inInclusiveRange(120, 1000));
      final near = settlePageTurn(progress: 0.95, velocityX: 0, base: slowBase);
      expect(
        near.duration.inMilliseconds,
        lessThan(r.duration.inMilliseconds),
        reason: '剩得越少补得越快',
      );
      // 默认 400ms 下两端都会被下限兜住，但也必须在合理区间内。
      final fast = settlePageTurn(progress: 0.5, velocityX: 0, base: base);
      expect(fast.duration.inMilliseconds, inInclusiveRange(120, 400));
    });

    test('拖得不够且不快 → 回弹（不翻页）', () {
      final r = settlePageTurn(progress: 0.2, velocityX: 10, base: base);
      expect(r.commit, isFalse);
      expect(r.duration.inMilliseconds, inInclusiveRange(120, 400));
    });

    test('轻扫（距离短但速度快）也能翻页', () {
      final r = settlePageTurn(progress: 0.15, velocityX: 900, base: base);
      expect(r.commit, isTrue);
    });

    test('方向反了的速度不算轻扫', () {
      final r = settlePageTurn(progress: 0.15, velocityX: -900, base: base);
      expect(r.commit, isFalse);
    });

    test('几乎没动就松手：极短补完时间也有下限', () {
      final r = settlePageTurn(progress: 0.01, velocityX: 0, base: base);
      expect(r.commit, isFalse);
      expect(r.duration.inMilliseconds, greaterThanOrEqualTo(kMinSettleMs));
    });
  });
}
