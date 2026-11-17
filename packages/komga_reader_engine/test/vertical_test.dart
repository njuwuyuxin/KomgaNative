import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:test/test.dart';

/// 表格化用例：纵向连续的几何全是算术，用表驱动比一长串 if 更好核对。
void main() {
  /// 浮点比较：700 / 0.7 = 1000.0000000000001，几何断言不能要求"连误差都没有"。
  void expectClose(List<double> actual, List<double> expected) {
    expect(actual.length, expected.length);
    for (var i = 0; i < actual.length; i++) {
      expect(actual[i], closeTo(expected[i], 1e-6), reason: 'index $i');
    }
  }

  /// 三个已知尺寸的页：0.7 → 1000 高；0.5 → 1400 高；未知 → 兜底 0.7 → 1000 高。
  PageAspect aspectAt(int index) => switch (index) {
    0 => const PageAspect(width: 700, height: 1000),
    1 => const PageAspect(width: 500, height: 1000),
    _ => const PageAspect.unknown(),
  };

  group('computeVerticalLayout', () {
    test('按视口宽度等比缩放，高度 = 宽度 / 宽高比', () {
      final layout = computeVerticalLayout(
        pageCount: 3,
        viewportWidth: 700,
        aspectAt: aspectAt,
      );

      expectClose(layout.pageHeights, <double>[1000, 1400, 1000]);
      expectClose(layout.offsets, <double>[0, 1000, 2400]);
      expect(layout.totalHeight, closeTo(3400, 1e-6));
      expect(layout.pageCount, 3);
      expect(layout.isEmpty, isFalse);
    });

    test('页间距计入偏移，但不计入总高（最后一页之后没有间距）', () {
      final layout = computeVerticalLayout(
        pageCount: 3,
        viewportWidth: 700,
        aspectAt: aspectAt,
        gap: 10,
      );

      expectClose(layout.offsets, <double>[0, 1010, 2420]);
      expect(layout.totalHeight, closeTo(3420, 1e-6));
    });

    test('宽度为 0 时高度全 0，不产生 NaN/负高度', () {
      final layout = computeVerticalLayout(
        pageCount: 2,
        viewportWidth: 0,
        aspectAt: aspectAt,
      );
      expectClose(layout.pageHeights, <double>[0, 0]);
      expect(layout.totalHeight, 0);
    });

    test('0 页返回空布局（不是异常）', () {
      final layout = computeVerticalLayout(
        pageCount: 0,
        viewportWidth: 700,
        aspectAt: aspectAt,
      );
      expect(layout.isEmpty, isTrue);
      expect(layout.totalHeight, 0);
      expect(layout.pageCount, 0);
    });

    test('宽高比未知时用兜底值，不同兜底值只影响高度', () {
      final layout = computeVerticalLayout(
        pageCount: 1,
        viewportWidth: 700,
        aspectAt: (_) => const PageAspect.unknown(),
        fallbackAspectRatio: 0.5,
      );
      expect(layout.pageHeights.single, closeTo(1400, 1e-6));

      final fallback = computeVerticalLayout(
        pageCount: 1,
        viewportWidth: 700,
        aspectAt: (_) => const PageAspect.unknown(),
      );
      expect(fallback.pageHeights.single, closeTo(1000, 1e-6));
    });
  });

  group('pageAtViewportCenter', () {
    final layout = computeVerticalLayout(
      pageCount: 3,
      viewportWidth: 700,
      aspectAt: aspectAt,
    );

    int at(double scroll, {double viewport = 800}) => pageAtViewportCenter(
      layout,
      scrollOffset: scroll,
      viewportHeight: viewport,
    );

    test('顶部 → 第一页', () {
      expect(at(0), 0);
      expect(at(100), 0);
    });

    test('中心落在第二页中间 → 第二页', () {
      // center = 900 + 400 = 1300，落在 [1000, 2400)
      expect(at(900), 1);
    });

    test('中心越过页边界一点点 → 下一页', () {
      // 第二页顶部约 1000；center = 600.5 + 400 = 1000.5
      expect(at(600.5), 1);
    });

    test('滚到底 → 最后一页，不会越界', () {
      expect(at(3400), 2);
      expect(at(99999), 2);
    });

    test('回弹到负数 → 夹到第一页', () {
      expect(at(-500), 0);
    });

    test('单页布局恒为 0', () {
      final single = computeVerticalLayout(
        pageCount: 1,
        viewportWidth: 700,
        aspectAt: (_) => const PageAspect(width: 700, height: 1000),
      );
      expect(
        pageAtViewportCenter(single, scrollOffset: 500, viewportHeight: 800),
        0,
      );
    });

    test('页间距里 → 归上一页（不会因为缝隙抖动）', () {
      final gapped = computeVerticalLayout(
        pageCount: 3,
        viewportWidth: 700,
        aspectAt: aspectAt,
        gap: 200,
      );
      // 第二页顶部在 1220；center 1150 落在 1000..1220 的缝隙里
      expect(
        pageAtViewportCenter(gapped, scrollOffset: 750, viewportHeight: 800),
        0,
      );
    });

    test('空布局返回 0 而不是抛异常', () {
      expect(
        pageAtViewportCenter(
          VerticalLayout.empty,
          scrollOffset: 100,
          viewportHeight: 800,
        ),
        0,
      );
    });
  });

  group('scrollOffsetForPage', () {
    final layout = computeVerticalLayout(
      pageCount: 3,
      viewportWidth: 700,
      aspectAt: aspectAt,
    );

    test('跳到第 N 页 = 该页顶部偏移', () {
      expect(scrollOffsetForPage(layout, 0), 0);
      expect(scrollOffsetForPage(layout, 1), closeTo(1000, 1e-6));
      expect(scrollOffsetForPage(layout, 2), closeTo(2400, 1e-6));
    });

    test('越界夹紧到首/尾', () {
      expect(scrollOffsetForPage(layout, -3), 0);
      expect(scrollOffsetForPage(layout, 99), closeTo(2400, 1e-6));
    });

    test('与 pageAtViewportCenter 往返一致', () {
      for (var page = 0; page < layout.pageCount; page++) {
        final offset = scrollOffsetForPage(layout, page);
        expect(
          pageAtViewportCenter(
            layout,
            scrollOffset: offset,
            viewportHeight: 400,
          ),
          page,
          reason: '第 $page 页跳过去后应仍停在那一页',
        );
      }
    });

    test('空布局返回 0', () {
      expect(scrollOffsetForPage(VerticalLayout.empty, 2), 0);
    });
  });
}
