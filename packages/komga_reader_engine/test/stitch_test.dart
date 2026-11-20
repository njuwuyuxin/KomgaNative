import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:test/test.dart';

void main() {
  group('computeStitchLayout', () {
    test('等高双页 1:1 无缝横向拼接', () {
      final layout = computeStitchLayout(
        leftWidth: 800,
        leftHeight: 1200,
        rightWidth: 820,
        rightHeight: 1200,
      );

      expect(layout.isEmpty, isFalse);
      expect(layout.width, 1620);
      expect(layout.height, 1200);
      expect(layout.left, const RectD(0, 0, 800, 1200));
      expect(layout.right, const RectD(800, 0, 820, 1200));
    });

    test('不等高双页按较高一侧等比对齐高度，不丢高分细节', () {
      final layout = computeStitchLayout(
        leftWidth: 400,
        leftHeight: 600,
        rightWidth: 800,
        rightHeight: 1200,
      );

      expect(layout.width, 1600);
      expect(layout.height, 1200);
      expect(layout.left, const RectD(0, 0, 800, 1200));
      expect(layout.right, const RectD(800, 0, 800, 1200));
    });

    test('超大图超出 maxDimension 时整体等比收敛到纹理上限内', () {
      final layout = computeStitchLayout(
        leftWidth: 5000,
        leftHeight: 7000,
        rightWidth: 5000,
        rightHeight: 7000,
        maxDimension: 4000,
      );

      expect(layout.width, 4000);
      expect(layout.height, 2800);
      expect(layout.left, const RectD(0, 0, 2000, 2800));
      expect(layout.right, const RectD(2000, 0, 2000, 2800));
    });

    test('0 或负数等非法尺寸返回 empty', () {
      expect(
        computeStitchLayout(
          leftWidth: 0,
          leftHeight: 1200,
          rightWidth: 800,
          rightHeight: 1200,
        ).isEmpty,
        isTrue,
      );
      expect(
        computeStitchLayout(
          leftWidth: 800,
          leftHeight: -1,
          rightWidth: 800,
          rightHeight: 1200,
        ).isEmpty,
        isTrue,
      );
      expect(
        computeStitchLayout(
          leftWidth: 800,
          leftHeight: 1200,
          rightWidth: 800,
          rightHeight: 1200,
          maxDimension: 1,
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('resolveSavePages', () {
    test('单页与纵向滚动只导出当前单页', () {
      expect(
        resolveSavePages(
          mode: ReadingMode.paged,
          currentPage: 3,
          spread: const <int>[2],
          rightToLeft: true,
        ),
        const <int>[3],
      );
      expect(
        resolveSavePages(
          mode: ReadingMode.verticalScroll,
          currentPage: 5,
          spread: const <int>[4],
          rightToLeft: false,
        ),
        const <int>[5],
      );
    });

    test('双页模式遇到单独封面或跨页宽图时只导出单张，不重复拼接', () {
      expect(
        resolveSavePages(
          mode: ReadingMode.doublePage,
          currentPage: 1,
          spread: const <int>[0],
          rightToLeft: true,
        ),
        const <int>[1],
      );
      expect(
        resolveSavePages(
          mode: ReadingMode.doublePage,
          currentPage: 4,
          spread: const <int>[3],
          rightToLeft: false,
        ),
        const <int>[4],
      );
    });

    test('双页模式 LTR 为 [前页, 后页]，RTL 日漫翻转为 [后页, 前页]', () {
      expect(
        resolveSavePages(
          mode: ReadingMode.doublePage,
          currentPage: 2,
          spread: const <int>[1, 2],
          rightToLeft: false,
        ),
        const <int>[2, 3],
      );
      expect(
        resolveSavePages(
          mode: ReadingMode.doublePage,
          currentPage: 2,
          spread: const <int>[1, 2],
          rightToLeft: true,
        ),
        const <int>[3, 2],
      );
    });
  });

  group('sniffImageFormat & formatSavedPageFileName', () {
    test('识别常见图片魔数，未知或过短兜底为 PNG', () {
      expect(
        sniffImageFormat(const <int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]),
        ImageFileFormat.png,
      );
      expect(
        sniffImageFormat(const <int>[0xFF, 0xD8, 0xFF, 0xE0]),
        ImageFileFormat.jpeg,
      );
      expect(
        sniffImageFormat(const <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
        ImageFileFormat.gif,
      );
      expect(
        sniffImageFormat(const <int>[
          0x52,
          0x49,
          0x46,
          0x46,
          0x00,
          0x00,
          0x00,
          0x00,
          0x57,
          0x45,
          0x42,
          0x50,
        ]),
        ImageFileFormat.webp,
      );
      expect(
        sniffImageFormat(const <int>[
          0x00,
          0x00,
          0x00,
          0x1C,
          0x66,
          0x74,
          0x79,
          0x70,
          0x61,
          0x76,
          0x69,
          0x66,
        ]),
        ImageFileFormat.avif,
      );
      expect(sniffImageFormat(const <int>[]), ImageFileFormat.png);
      expect(sniffImageFormat(const <int>[1, 2, 3]), ImageFileFormat.png);
    });

    test('文件名带页码或跨页区间，并过滤非法路径字符', () {
      expect(
        formatSavedPageFileName(
          bookId: 'b1',
          pages: const <int>[2],
          extension: 'jpg',
        ),
        'komganative-b1-page-2.jpg',
      );
      expect(
        formatSavedPageFileName(
          bookId: 'book/01:a',
          pages: const <int>[3, 2],
          extension: 'png',
        ),
        'komganative-book_01_a-pages-2-3.png',
      );
    });
  });
}
