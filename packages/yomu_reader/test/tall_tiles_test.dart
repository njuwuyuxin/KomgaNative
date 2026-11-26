import 'package:test/test.dart';
import 'package:yomu_reader/yomu_reader.dart';

void main() {
  group('computeTallImageTiles', () {
    test('未超阈值或非法尺寸返回空（普通整页渲染）', () {
      expect(computeTallImageTiles(width: 800, height: 1200), isEmpty);
      expect(computeTallImageTiles(width: 800, height: 4096), isEmpty);
      expect(computeTallImageTiles(width: 0, height: 8000), isEmpty);
      expect(computeTallImageTiles(width: 800, height: -1), isEmpty);
      expect(
        computeTallImageTiles(width: 800, height: 8000, maxTileHeight: 0),
        isEmpty,
      );
    });

    test('4097px 刚好触发分片并无缝覆盖全部像素高度', () {
      final tiles = computeTallImageTiles(width: 1080, height: 4097);
      expect(tiles.length, 3);
      expect(tiles[0].srcTop, 0);
      expect(tiles[0].srcBottom, 2048);
      expect(tiles[1].srcTop, 2048);
      expect(tiles[1].srcBottom, 4096);
      expect(tiles[2].srcTop, 4096);
      expect(tiles[2].srcBottom, 4097);
      expect(tiles[2].srcHeight, 1);
    });

    test('16000px 巨型条漫分片连续零缝隙且每片不超过上限', () {
      final tiles = computeTallImageTiles(width: 1080, height: 16000);
      expect(tiles.length, 8);
      expect(tiles.first.srcTop, 0);
      expect(tiles.last.srcBottom, 16000);
      for (var i = 0; i < tiles.length; i++) {
        expect(tiles[i].index, i);
        expect(
          tiles[i].srcHeight,
          inInclusiveRange(1, kTallImageMaxTileHeight),
        );
        if (i > 0) {
          expect(tiles[i].srcTop, tiles[i - 1].srcBottom);
        }
      }
      expect(tiles.first.topFraction, 0.0);
      expect(tiles.last.bottomFraction, 1.0);
    });
  });

  group('buildVerticalRenderSlots', () {
    test('混合普通页与超长页时，每页分片总高度严格等于 VerticalLayout.pageHeights', () {
      final sizes = <({int? width, int? height})>[
        (width: 800, height: 1200),
        (width: 800, height: 12000),
        (width: null, height: null),
      ];
      final layout = computeVerticalLayout(
        pageCount: sizes.length,
        viewportWidth: 400,
        aspectAt: (i) => PageAspect(
          width: sizes[i].width?.toDouble(),
          height: sizes[i].height?.toDouble(),
        ),
      );
      final slots = buildVerticalRenderSlots(
        layout: layout,
        sizeAt: (i) => sizes[i],
      );

      // 第 0 页 1 槽 + 第 1 页 6 槽（12000 / 2048 = 5.86 -> 6）+ 第 2 页 1 槽 = 8 槽
      expect(slots.length, 8);
      expect(slots.first.isTiled, isFalse);
      expect(slots.last.isTiled, isFalse);

      final page1Slots = slots.where((s) => s.pageIndex == 1).toList();
      expect(page1Slots.length, 6);
      final sumHeight = page1Slots.fold<double>(
        0,
        (a, b) => a + b.displayHeight,
      );
      expect(sumHeight, closeTo(layout.pageHeights[1], 1e-6));
    });
  });
}
