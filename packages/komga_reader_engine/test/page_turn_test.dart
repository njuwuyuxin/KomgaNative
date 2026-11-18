import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:test/test.dart';

/// 翻页卷曲的几何：起手必须从角上掀、收尾必须贴书脊立直、进度到 1 时整页翻走。
void main() {
  const width = 1000.0;
  const height = 1500.0;

  group('curlGeometry', () {
    test('进度 0：折线穿过左下角，倾角最大', () {
      final g = curlGeometry(progress: 0, width: width, height: height);
      expect(g.foldX, 0);
      expect(g.foldY, height);
      expect(g.tilt, closeTo(kCurlTilt, 1e-9));
      expect(g.startsAtCorner, isTrue, reason: '起手是"捏住左下角"，不是整条边一起抬');
    });

    test('进度 1：折线与书脊重合、倾角为 0（竖直线）', () {
      final g = curlGeometry(progress: 1, width: width, height: height);
      expect(g.foldX, closeTo(width, 1e-9));
      expect(g.tilt, closeTo(0, 1e-9));
    });

    test('倾角随进度单调减小（越翻越立直）', () {
      var previous = double.infinity;
      for (var i = 0; i <= 20; i++) {
        final g = curlGeometry(progress: i / 20, width: width, height: height);
        expect(g.tilt, lessThanOrEqualTo(previous + 1e-9));
        previous = g.tilt;
      }
    });

    test('折线位置单调右移，并且不是线性推进（慢—快—慢）', () {
      var previous = -1.0;
      final positions = <double>[];
      for (var i = 0; i <= 20; i++) {
        final g = curlGeometry(progress: i / 20, width: width, height: height);
        expect(g.foldX, greaterThan(previous));
        previous = g.foldX;
        positions.add(g.foldX);
      }
      final firstQuarter = positions[5] - positions[0];
      final middleQuarter = positions[10] - positions[5];
      final lastQuarter = positions[20] - positions[15];
      // 起手和收尾都比中段慢：这就是"掀角"和"贴上书脊"的手感。
      expect(firstQuarter, lessThan(middleQuarter));
      expect(lastQuarter, lessThan(middleQuarter));
    });

    test('起手是从左下角掀起：左下角先翻，左上角还是平的', () {
      // 回归测试：法线 y 分量写反时被掀起的是"左上"那半边，
      // 真机上看起来像"从左上角翻页"，而且 p 刚离开 0 就几乎整页翻掉（跳变）。
      //
      // 只检查前 30%：再往后折线已经扫过左半边，左上角本来就该翻走了。
      for (var step = 1; step <= 3; step++) {
        final g = curlGeometry(
          progress: step / 10,
          width: width,
          height: height,
        );
        double s(double x, double y) =>
            (x - g.foldX) * g.normalX + (y - g.foldY) * g.normalY;
        expect(s(2, height - 2), lessThan(0), reason: '左下角应该先被掀起');
        expect(s(2, height * 0.4), greaterThan(0), reason: '左上方还没翻走');
      }
    });

    test('起手进度很小时只掀起一个角，不会直接跳到半页', () {
      final g = curlGeometry(progress: 0.02, width: width, height: height);
      // 折线仍在最左边 3% 以内；法线方向错了的话它会瞬间扫到中间。
      expect(g.foldX, lessThan(width * 0.03));
    });

    test('中途：还没翻走的那一侧仍然是 s > 0', () {
      final g = curlGeometry(progress: 0.5, width: width, height: height);
      // 页面右侧（靠书脊）还没翻走。
      final right =
          (width - 5 - g.foldX) * g.normalX +
          (height / 2 - g.foldY) * g.normalY;
      expect(right, greaterThan(0));
      // 左侧已经被掀起来了。
      final left =
          (5 - g.foldX) * g.normalX + (height / 2 - g.foldY) * g.normalY;
      expect(left, lessThan(0));
    });

    test('镜像（LTR）：起手从右下角掀，收尾贴左边书脊', () {
      final start = curlGeometry(
        progress: 0,
        width: width,
        height: height,
        mirrored: true,
      );
      expect(start.foldX, closeTo(width, 1e-9));
      expect(start.startsAtCorner, isTrue);
      expect(start.normalX, lessThan(0), reason: 'LTR 时"没翻走"的一侧在右边');

      final end = curlGeometry(
        progress: 1,
        width: width,
        height: height,
        mirrored: true,
      );
      expect(end.foldX, closeTo(0, 1e-9));
      expect(end.tilt, closeTo(0, 1e-9));
    });

    test('卷筒随翻动变粗：起手只是一个翘起的页脚', () {
      final start = curlGeometry(progress: 0, width: width, height: height);
      final mid = curlGeometry(progress: 0.65, width: width, height: height);
      final end = curlGeometry(progress: 1, width: width, height: height);

      expect(start.radius, lessThan(mid.radius), reason: '起手不该就卷成一根筒');
      expect(
        start.radius,
        lessThan(width * kCurlRadiusRatio * 0.3),
        reason: '起手半径应该是最大值的零头',
      );
      expect(mid.radius, closeTo(width * kCurlRadiusRatio, 1e-6));
      expect(end.radius, closeTo(mid.radius, 1e-9), reason: '长到最大之后保持');
    });

    test('窄页也不会出现 0 半径', () {
      final g = curlGeometry(progress: 0.5, width: 2, height: 3);
      expect(g.radius, greaterThan(0));
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
