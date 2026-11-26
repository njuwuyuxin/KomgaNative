import 'package:test/test.dart';
import 'package:yomu_reader/yomu_reader.dart';

void main() {
  group('buildImageFilterMatrix', () {
    test('none 返回 20 元素单位矩阵，任意像素不变', () {
      final m = buildImageFilterMatrix(ReaderImageFilter.none);
      expect(m.length, 20);
      expect(applyColorMatrixToRgb(m, 123, 45, 210), (r: 123, g: 45, b: 210));
    });

    test('einkCrisp 将浅灰底纸漂白为纯白并加深黑线且输出纯灰阶', () {
      final m = buildImageFilterMatrix(ReaderImageFilter.einkCrisp);
      // 浅灰底纸 RGB(235, 232, 225) → 纯白 (255, 255, 255)
      expect(applyColorMatrixToRgb(m, 235, 232, 225), (r: 255, g: 255, b: 255));
      // 深灰墨线 RGB(18, 18, 18) → 纯黑 (0, 0, 0)
      expect(applyColorMatrixToRgb(m, 18, 18, 18), (r: 0, g: 0, b: 0));
      // 彩色像素转为等值灰阶
      final gray = applyColorMatrixToRgb(m, 180, 90, 60);
      expect(gray.r, gray.g);
      expect(gray.g, gray.b);
    });

    test('vintageDeYellow 漂白偏黄纸底并保留彩页色彩', () {
      final m = buildImageFilterMatrix(ReaderImageFilter.vintageDeYellow);
      // 发黄老纸 RGB(240, 234, 212) → 纯白 (255, 255, 255)
      expect(applyColorMatrixToRgb(m, 240, 234, 212), (r: 255, g: 255, b: 255));
      // 红色彩图保持明显红色倾向
      final red = applyColorMatrixToRgb(m, 200, 60, 50);
      expect(red.r, greaterThan(red.g + 100));
    });

    test('custom 支持参数夹紧与 JSON 往返', () {
      const f = ReaderImageFilter(
        preset: ReaderImageFilterPreset.custom,
        contrast: 1.6,
        whiteThreshold: 215,
        grayscale: true,
      );
      final parsed = ReaderImageFilter.fromJson(f.toJson());
      expect(parsed, f);

      // 非法/越界 JSON 自动夹紧不崩
      final clamped = ReaderImageFilter.fromJson(<String, Object?>{
        'preset': 'custom',
        'contrast': 9.9,
        'whiteThreshold': 50,
        'grayscale': false,
      });
      expect(clamped.contrast, ReaderImageFilter.maxContrast);
      expect(clamped.whiteThreshold, ReaderImageFilter.minWhiteThreshold);
      expect(ReaderImageFilter.fromJson('bad'), ReaderImageFilter.none);
    });
  });
}
