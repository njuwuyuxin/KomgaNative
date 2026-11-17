import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:test/test.dart';

void main() {
  const portraitPage = (w: 1000, h: 1500); // 2:3
  const phoneViewport = SizeD(390, 844);
  const tabletViewport = SizeD(1024, 768);

  group('fitScaleFor', () {
    test('contain 取较小的缩放比（竖图在竖屏里由宽度或高度决定）', () {
      final scale = fitScaleFor(
        pageWidth: portraitPage.w,
        pageHeight: portraitPage.h,
        viewport: phoneViewport,
        mode: FitMode.contain,
      );
      // 390/1000 = 0.39, 844/1500 = 0.5627 → 取 0.39
      expect(scale, closeTo(0.39, 1e-9));
    });

    test('fitWidth / fitHeight / original 的行为', () {
      expect(
        fitScaleFor(
          pageWidth: 1000,
          pageHeight: 1500,
          viewport: phoneViewport,
          mode: FitMode.fitWidth,
        ),
        closeTo(0.39, 1e-9),
      );
      expect(
        fitScaleFor(
          pageWidth: 1000,
          pageHeight: 1500,
          viewport: tabletViewport,
          mode: FitMode.fitHeight,
        ),
        closeTo(768 / 1500, 1e-9),
      );
      expect(
        fitScaleFor(
          pageWidth: 1000,
          pageHeight: 1500,
          viewport: tabletViewport,
          mode: FitMode.original,
        ),
        1.0,
      );
    });

    test('非法尺寸返回 1 而不是 NaN/无穷', () {
      expect(
        fitScaleFor(
          pageWidth: 0,
          pageHeight: 100,
          viewport: phoneViewport,
          mode: FitMode.contain,
        ),
        1,
      );
      expect(
        fitScaleFor(
          pageWidth: 100,
          pageHeight: 100,
          viewport: const SizeD(0, 0),
          mode: FitMode.contain,
        ),
        1,
      );
    });
  });

  group('computePagedLayout', () {
    test('未放大时整页居中', () {
      final layout = computePagedLayout(
        pageWidth: portraitPage.w,
        pageHeight: portraitPage.h,
        viewport: phoneViewport,
      );
      expect(layout.scale, closeTo(0.39, 1e-9));
      expect(layout.isZoomedIn, isFalse);
      expect(
        layout.content.height,
        lessThanOrEqualTo(phoneViewport.height + 0.001),
      );
      expect(layout.content.left, closeTo(0, 0.001)); // 宽度铺满
      expect(
        layout.content.top,
        closeTo((phoneViewport.height - layout.content.height) / 2, 0.001),
      );
    });

    test('缩放被夹在 [fit, max(fit*4, 1)] 区间', () {
      final fit = fitScaleFor(
        pageWidth: portraitPage.w,
        pageHeight: portraitPage.h,
        viewport: phoneViewport,
        mode: FitMode.contain,
      );
      final tooSmall = computePagedLayout(
        pageWidth: portraitPage.w,
        pageHeight: portraitPage.h,
        viewport: phoneViewport,
        zoomFactor: 0.1,
      );
      expect(tooSmall.scale, closeTo(fit, 1e-9));

      final tooBig = computePagedLayout(
        pageWidth: portraitPage.w,
        pageHeight: portraitPage.h,
        viewport: phoneViewport,
        zoomFactor: 100,
      );
      expect(tooBig.scale, closeTo(fit * 4, 1e-9));
    });

    test('放大后平移被夹紧，不会露出空白边', () {
      final layout = computePagedLayout(
        pageWidth: portraitPage.w,
        pageHeight: portraitPage.h,
        viewport: phoneViewport,
        zoomFactor: 3,
        panX: -99999,
        panY: -99999,
      );
      expect(layout.content.left, lessThanOrEqualTo(0));
      expect(layout.content.top, lessThanOrEqualTo(0));
      expect(
        layout.content.right,
        greaterThanOrEqualTo(phoneViewport.width - 0.001),
      );
      expect(
        layout.content.bottom,
        greaterThanOrEqualTo(phoneViewport.height - 0.001),
      );
    });

    test('放大后向右下拖动被夹到 0', () {
      final layout = computePagedLayout(
        pageWidth: portraitPage.w,
        pageHeight: portraitPage.h,
        viewport: phoneViewport,
        zoomFactor: 3,
        panX: 500,
        panY: 500,
      );
      expect(layout.content.left, 0);
      expect(layout.content.top, 0);
    });
  });
}
