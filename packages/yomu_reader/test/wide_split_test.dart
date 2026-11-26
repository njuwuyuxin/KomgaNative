import 'package:test/test.dart';
import 'package:yomu_reader/yomu_reader.dart';

void main() {
  group('WidePageSplitMode.isActive', () {
    test('仅在单页翻页模式下按横竖屏生效', () {
      expect(
        WidePageSplitMode.off.isActive(
          mode: ReadingMode.paged,
          landscape: false,
        ),
        isFalse,
      );
      expect(
        WidePageSplitMode.autoPortrait.isActive(
          mode: ReadingMode.paged,
          landscape: false,
        ),
        isTrue,
      );
      expect(
        WidePageSplitMode.autoPortrait.isActive(
          mode: ReadingMode.paged,
          landscape: true,
        ),
        isFalse,
      );
      expect(
        WidePageSplitMode.always.isActive(
          mode: ReadingMode.paged,
          landscape: true,
        ),
        isTrue,
      );
      expect(
        WidePageSplitMode.always.isActive(
          mode: ReadingMode.doublePage,
          landscape: false,
        ),
        isFalse,
      );
      expect(
        WidePageSplitMode.always.isActive(
          mode: ReadingMode.verticalScroll,
          landscape: false,
        ),
        isFalse,
      );
    });
  });

  group('buildSplitFrames', () {
    test('0 页返回空列表', () {
      expect(
        buildSplitFrames(
          pageCount: 0,
          aspectAt: (_) => const PageAspect.unknown(),
          rightToLeft: true,
        ),
        isEmpty,
      );
    });

    test('RTL 宽页按先右后左拆成两帧，普通页与未知尺寸页保持 full', () {
      final aspects = <PageAspect>[
        const PageAspect(width: 800, height: 1200), // 封面
        const PageAspect(width: 1800, height: 1200), // 宽页（ratio 1.5）
        const PageAspect.unknown(), // 未知尺寸
      ];
      final frames = buildSplitFrames(
        pageCount: aspects.length,
        aspectAt: (i) => aspects[i],
        rightToLeft: true,
      );
      expect(frames, const <SplitFrame>[
        SplitFrame(pageIndex: 0, half: PageHalf.full),
        SplitFrame(pageIndex: 1, half: PageHalf.right),
        SplitFrame(pageIndex: 1, half: PageHalf.left),
        SplitFrame(pageIndex: 2, half: PageHalf.full),
      ]);
      expect(frames[1].pageNumber, 2);
      expect(frames[2].pageNumber, 2);
    });

    test('LTR 宽页按先左后右拆成两帧', () {
      final frames = buildSplitFrames(
        pageCount: 1,
        aspectAt: (_) => const PageAspect(width: 2000, height: 1200),
        rightToLeft: false,
      );
      expect(frames, const <SplitFrame>[
        SplitFrame(pageIndex: 0, half: PageHalf.left),
        SplitFrame(pageIndex: 0, half: PageHalf.right),
      ]);
    });

    test('mergedPageIndex 使指定宽页临时合页为单帧 full', () {
      final frames = buildSplitFrames(
        pageCount: 2,
        aspectAt: (_) => const PageAspect(width: 2000, height: 1200),
        rightToLeft: true,
        mergedPageIndex: 0,
      );
      expect(frames, const <SplitFrame>[
        SplitFrame(pageIndex: 0, half: PageHalf.full),
        SplitFrame(pageIndex: 1, half: PageHalf.right),
        SplitFrame(pageIndex: 1, half: PageHalf.left),
      ]);
    });

    test('resolveSplitFrameIndex 精确匹配 preferredHalf 并在找不到时回落首帧', () {
      final frames = buildSplitFrames(
        pageCount: 2,
        aspectAt: (i) => i == 1
            ? const PageAspect(width: 2000, height: 1200)
            : const PageAspect(width: 800, height: 1200),
        rightToLeft: true,
      );
      expect(
        resolveSplitFrameIndex(
          frames,
          pageIndex: 1,
          preferredHalf: PageHalf.left,
        ),
        2,
      );
      expect(
        resolveSplitFrameIndex(
          frames,
          pageIndex: 1,
          preferredHalf: PageHalf.right,
        ),
        1,
      );
      expect(
        resolveSplitFrameIndex(
          frames,
          pageIndex: 1,
          preferredHalf: PageHalf.full,
        ),
        1,
      );
      expect(resolveSplitFrameIndex(frames, pageIndex: 99), frames.length - 1);
    });

    test('PageHalf 裁切比例与有效宽度计算', () {
      expect(PageHalf.full.horizontalFraction, (left: 0.0, right: 1.0));
      expect(PageHalf.left.horizontalFraction, (left: 0.0, right: 0.5));
      expect(PageHalf.right.horizontalFraction, (left: 0.5, right: 1.0));
      expect(PageHalf.full.effectiveWidth(1800), 1800);
      expect(PageHalf.left.effectiveWidth(1801), 901);
      expect(PageHalf.right.effectiveWidth(1), 1);
    });
  });
}
