import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:test/test.dart';

void main() {
  PageAspect normal() => const PageAspect(width: 1000, height: 1500);
  PageAspect wide() => const PageAspect(width: 2000, height: 1000);

  group('buildSpreads', () {
    test('封面单独成页，后续两两配对', () {
      final spreads = buildSpreads(pageCount: 6, aspectAt: (_) => normal());
      expect(spreads, [
        [0],
        [1, 2],
        [3, 4],
        [5],
      ]);
    });

    test('宽页独占一屏，且不影响后续配对', () {
      final spreads = buildSpreads(
        pageCount: 6,
        aspectAt: (i) => i == 3 ? wide() : normal(),
      );
      expect(spreads, [
        [0],
        [1, 2],
        [3],
        [4, 5],
      ]);
    });

    test('coverSolo=false 时从第一页就开始配对', () {
      final spreads = buildSpreads(
        pageCount: 3,
        aspectAt: (_) => normal(),
        coverSolo: false,
      );
      expect(spreads, [
        [0, 1],
        [2],
      ]);
    });

    test('尺寸未知按普通页处理（不能因为缺宽高就错位）', () {
      final spreads = buildSpreads(
        pageCount: 3,
        aspectAt: (_) => const PageAspect.unknown(),
      );
      expect(spreads, [
        [0],
        [1, 2],
      ]);
    });

    test('0 页返回空', () {
      expect(buildSpreads(pageCount: 0, aspectAt: (_) => normal()), isEmpty);
    });

    test('groupFrom 从指定页重新配对（UI-P3-5）', () {
      // 默认 [0],[1,2],[3,4],[5]；从第 3 页（0 基 2）开始 → [0],[1],[2,3],[4,5]。
      final spreads = buildSpreads(
        pageCount: 6,
        aspectAt: (_) => normal(),
        groupFrom: 2,
      );
      expect(spreads, [
        [0],
        [1],
        [2, 3],
        [4, 5],
      ]);
    });

    test('groupFrom 落在默认跨页中间时，前一页单独留下', () {
      final spreads = buildSpreads(
        pageCount: 7,
        aspectAt: (_) => normal(),
        groupFrom: 4,
      );
      expect(spreads, [
        [0],
        [1, 2],
        [3],
        [4, 5],
        [6],
      ]);
    });

    test('groupFrom 遇到宽页仍然单独成屏', () {
      final spreads = buildSpreads(
        pageCount: 6,
        aspectAt: (i) => i == 4 ? wide() : normal(),
        groupFrom: 2,
      );
      expect(spreads, [
        [0],
        [1],
        [2, 3],
        [4],
        [5],
      ]);
    });
  });

  group('visualOrder', () {
    test('RTL 时双页左右互换，封面不换', () {
      expect(visualOrder([4, 5], rightToLeft: true), [5, 4]);
      expect(visualOrder([4, 5], rightToLeft: false), [4, 5]);
      expect(visualOrder([0], rightToLeft: true), [0]);
    });

    test('返回不可变列表，防止 UI 误改', () {
      final order = visualOrder([1, 2], rightToLeft: false);
      expect(() => order.add(3), throwsUnsupportedError);
    });
  });

  group('spreadIndexOf', () {
    test('找到页所在的跨页，越界返回 -1', () {
      final spreads = [
        [0],
        [1, 2],
        [3],
      ];
      expect(spreadIndexOf(spreads, 0), 0);
      expect(spreadIndexOf(spreads, 2), 1);
      expect(spreadIndexOf(spreads, 3), 2);
      expect(spreadIndexOf(spreads, 99), -1);
    });
  });
}
