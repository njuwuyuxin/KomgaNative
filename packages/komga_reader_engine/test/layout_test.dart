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

    group('cover（填满屏幕）', () {
      test('取两个方向里更大的比例，宽的溢出、高的不溢出', () {
        // 390/1000 = 0.39, 844/1500 = 0.5627 → cover 取 0.5627
        final scale = fitScaleFor(
          pageWidth: portraitPage.w,
          pageHeight: portraitPage.h,
          viewport: phoneViewport,
          mode: FitMode.cover,
        );
        expect(scale, closeTo(844 / 1500, 1e-9));

        final layout = computePagedLayout(
          pageWidth: portraitPage.w,
          pageHeight: portraitPage.h,
          viewport: phoneViewport,
          fit: FitMode.cover,
        );
        expect(layout.content.width, greaterThan(phoneViewport.width));
        expect(
          layout.content.height,
          closeTo(phoneViewport.height, 0.001),
          reason: '高度方向正好铺满',
        );
      });

      test('宽页在竖屏里 cover：横向溢出、纵向铺满', () {
        final layout = computePagedLayout(
          pageWidth: 2000,
          pageHeight: 1000,
          viewport: phoneViewport,
          fit: FitMode.cover,
        );
        expect(layout.content.width, greaterThan(phoneViewport.width));
        expect(layout.content.height, closeTo(phoneViewport.height, 0.001));
        expect(contentOverflows(layout, phoneViewport), isTrue);
      });

      test('溢出的方向可以平移，且被夹在不露白边的范围内', () {
        // 竖屏 + 宽页：横向溢出，向左拖到底。
        final layout = computePagedLayout(
          pageWidth: 2000,
          pageHeight: 1000,
          viewport: phoneViewport,
          fit: FitMode.cover,
          panX: -99999,
        );
        expect(
          layout.content.left,
          closeTo(phoneViewport.width - layout.content.width, 0.001),
        );
        expect(
          layout.content.right,
          closeTo(phoneViewport.width, 0.001),
          reason: '夹紧后右边缘贴住视口',
        );
      });

      test('cover 下没有任何方向溢出时不算溢出', () {
        // 正方形页 + 正方形视口：两个比例都是 1，正好铺满。
        final layout = computePagedLayout(
          pageWidth: 500,
          pageHeight: 500,
          viewport: const SizeD(500, 500),
          fit: FitMode.cover,
        );
        expect(contentOverflows(layout, const SizeD(500, 500)), isFalse);
      });
    });

    test('fitWidth 在超长页上纵向溢出（要能平移）', () {
      final layout = computePagedLayout(
        pageWidth: 800,
        pageHeight: 8000,
        viewport: phoneViewport,
        fit: FitMode.fitWidth,
      );
      expect(layout.content.height, greaterThan(phoneViewport.height));
      expect(contentOverflows(layout, phoneViewport), isTrue);
    });

    test('双页模式忽略 cover，仍按 contain（不能把另一页裁掉）', () {
      final layout = computePagedLayout(
        pageWidth: portraitPage.w,
        pageHeight: portraitPage.h,
        viewport: phoneViewport,
        fit: FitMode.cover,
        mode: ReadingMode.doublePage,
      );
      expect(layout.scale, closeTo(0.39, 1e-9));
      expect(contentOverflows(layout, phoneViewport), isFalse);
    });
  });

  group('zoomAboutFocal', () {
    test('焦点下的内容保持不动（以双指中点为基准，而不是左上角）', () {
      // 适配后内容左上角在 (0, 129.5)，以 (195, 422) 为焦点放大一倍。
      final origin = zoomAboutFocal(
        contentLeft: 0,
        contentTop: 129.5,
        scale: 0.39,
        nextScale: 0.78,
        focalX: 195,
        focalY: 422,
      );
      expect(origin.left, closeTo(-195, 1e-9));
      expect(origin.top, closeTo(422 - (422 - 129.5) * 2, 1e-9));

      // 焦点处的内容坐标缩放前后必须落在同一个屏幕位置。
      const focalContent = 500.0; // (195 - 0) / 0.39
      expect(origin.left + focalContent * 0.78, closeTo(195, 1e-9));
    });

    test('单指拖动（比例不变）只平移焦点位移', () {
      final origin = zoomAboutFocal(
        contentLeft: -100,
        contentTop: -200,
        scale: 0.78,
        nextScale: 0.78,
        focalX: 150,
        focalY: 400,
        focalDeltaX: 24,
        focalDeltaY: -36,
      );
      expect(origin.left, closeTo(-76, 1e-9));
      expect(origin.top, closeTo(-236, 1e-9));
    });

    test('缩小同样以焦点为基准（内容往焦点收）', () {
      final origin = zoomAboutFocal(
        contentLeft: -300,
        contentTop: -400,
        scale: 1.56,
        nextScale: 0.78,
        focalX: 195,
        focalY: 422,
      );
      expect(origin.left, closeTo(195 - (195 + 300) * 0.5, 1e-9));
      expect(origin.top, closeTo(422 - (422 + 400) * 0.5, 1e-9));
    });

    test('非法比例退化为只保留位移，不产生 NaN', () {
      final origin = zoomAboutFocal(
        contentLeft: 10,
        contentTop: 20,
        scale: 0,
        nextScale: 0,
        focalX: 100,
        focalY: 100,
        focalDeltaX: 5,
        focalDeltaY: 6,
      );
      expect(origin.left, 15);
      expect(origin.top, 26);
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
