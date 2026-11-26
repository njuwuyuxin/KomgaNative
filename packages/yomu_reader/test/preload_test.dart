import 'package:yomu_reader/yomu_reader.dart';
import 'package:test/test.dart';

/// 页图预取的"该取哪几页"。规矩只有一条：按**屏**算，不按页码加减。
void main() {
  group('preloadPlan（单页/纵向）', () {
    test('先下一屏，再更远，最后上一屏', () {
      expect(preloadPlan(pageIndex: 2, pageCount: 10), <int>[3, 4, 1]);
    });

    test('第一页没有上一屏', () {
      expect(preloadPlan(pageIndex: 0, pageCount: 10), <int>[1, 2]);
    });

    test('最后一页没有下一屏', () {
      expect(preloadPlan(pageIndex: 9, pageCount: 10), <int>[8]);
    });

    test('ahead / behind 可以分别关掉', () {
      expect(
        preloadPlan(pageIndex: 2, pageCount: 10, ahead: 1, behind: 0),
        <int>[3],
      );
      expect(
        preloadPlan(pageIndex: 2, pageCount: 10, ahead: 0, behind: 1),
        <int>[1],
      );
    });
  });

  group('preloadPlan（双页）', () {
    test('下一屏的两页都在计划里，不会只预取到第一页', () {
      // 封面单独一屏，之后两页一屏。
      final spreads = <List<int>>[
        <int>[0],
        <int>[1, 2],
        <int>[3, 4],
        <int>[5, 6],
      ];
      expect(preloadPlan(pageIndex: 1, pageCount: 7, spreads: spreads), <int>[
        3,
        4,
        5,
        6,
        0,
      ]);
    });

    test('宽页单独成屏时只预取那一页', () {
      final spreads = <List<int>>[
        <int>[0],
        <int>[1],
        <int>[2, 3],
      ];
      expect(
        preloadPlan(pageIndex: 0, pageCount: 4, spreads: spreads, behind: 0),
        <int>[1, 2, 3],
      );
    });

    test('屏幕内的第二页不会被当成"下一页"重复预取', () {
      final spreads = <List<int>>[
        <int>[0],
        <int>[1, 2],
        <int>[3, 4],
      ];
      // 第 2、3 页（0 基 1、2）已经在屏幕上，计划里不该出现。
      expect(
        preloadPlan(pageIndex: 1, pageCount: 5, spreads: spreads, behind: 0),
        <int>[3, 4],
      );
    });
  });

  group('preloadPlan（边界）', () {
    test('空书 / 越界 / 和分屏对不上都返回空计划', () {
      expect(preloadPlan(pageIndex: 0, pageCount: 0), isEmpty);
      expect(preloadPlan(pageIndex: -1, pageCount: 3), isEmpty);
      expect(preloadPlan(pageIndex: 3, pageCount: 3), isEmpty);
      expect(
        preloadPlan(
          pageIndex: 5,
          pageCount: 3,
          spreads: <List<int>>[
            <int>[0],
            <int>[1, 2],
          ],
        ),
        isEmpty,
        reason: '索引越界时不能把不存在的页塞进计划',
      );
    });

    test('单页的书没有可预取的页', () {
      expect(preloadPlan(pageIndex: 0, pageCount: 1), isEmpty);
    });

    test('返回的列表不可变，调用方改不动计划', () {
      final plan = preloadPlan(pageIndex: 0, pageCount: 5);
      expect(() => plan.add(9), throwsUnsupportedError);
    });
  });
}
