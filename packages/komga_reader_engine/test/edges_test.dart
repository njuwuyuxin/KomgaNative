import 'dart:typed_data';

import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:test/test.dart';

/// UI-P1-5 动态背景的提色算法。
///
/// 输入是**降采样之后的 RGBA**（由 Widget 层解码得到），所以这里可以用
/// 手写的小图直接构造，不需要真的图片解码器。
Uint8List rgbaImage(
  int width,
  int height,
  ({int r, int g, int b, int a}) Function(int x, int y) at,
) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = at(x, y);
      final offset = (y * width + x) * 4;
      bytes[offset] = p.r;
      bytes[offset + 1] = p.g;
      bytes[offset + 2] = p.b;
      bytes[offset + 3] = p.a;
    }
  }
  return bytes;
}

({int r, int g, int b, int a}) solid(int r, int g, int b, [int a = 255]) =>
    (r: r, g: g, b: b, a: a);

void main() {
  group('edgeColor', () {
    test('纯色图：整页都是同一个颜色', () {
      final bytes = rgbaImage(8, 8, (int x, int y) => solid(200, 30, 40));
      expect(
        edgeColor(rgba: bytes, width: 8, height: 8),
        const RgbColor(200, 30, 40),
      );
    });

    test('只看页边：中间的黑色正文不影响页边色', () {
      // 4 像素宽的页边是米白，中间是黑字块。
      final bytes = rgbaImage(
        12,
        12,
        (int x, int y) => x >= 4 && x < 8 && y >= 4 && y < 8
            ? solid(0, 0, 0)
            : solid(240, 235, 225),
      );
      final color = edgeColor(rgba: bytes, width: 12, height: 12, band: 4);
      expect(color, const RgbColor(240, 235, 225));
    });

    test('黑边扫描：页边是黑色时输出接近黑（不会因为中间白而被拉亮）', () {
      final bytes = rgbaImage(
        10,
        10,
        (int x, int y) => x < 2 || x >= 8 || y < 2 || y >= 8
            ? solid(0, 0, 0)
            : solid(255, 255, 255),
      );
      final color = edgeColor(rgba: bytes, width: 10, height: 10, band: 2);
      expect(color, const RgbColor(0, 0, 0));
      expect(color!.isDark, isTrue);
    });

    test('白边扫描：页边是白色时输出白，亮度判定为浅色', () {
      final bytes = rgbaImage(
        10,
        10,
        (int x, int y) => x < 2 || x >= 8 || y < 2 || y >= 8
            ? solid(255, 255, 255)
            : solid(0, 0, 0),
      );
      final color = edgeColor(rgba: bytes, width: 10, height: 10, band: 2);
      expect(color!.luminance, greaterThan(200));
      expect(color.isDark, isFalse);
    });

    test('透明像素被跳过：全透明返回 null', () {
      final bytes = rgbaImage(6, 6, (int x, int y) => solid(9, 9, 9, 0));
      expect(edgeColor(rgba: bytes, width: 6, height: 6), isNull);

      // 一半透明一半不透明：结果只由不透明的那部分决定。
      final half = rgbaImage(
        6,
        6,
        (int x, int y) => x < 3 ? solid(0, 0, 0, 0) : solid(120, 60, 30),
      );
      expect(
        edgeColor(rgba: half, width: 6, height: 6),
        const RgbColor(120, 60, 30),
      );
    });

    test('1×1 图退化成整图平均，不返回空', () {
      final bytes = rgbaImage(1, 1, (int x, int y) => solid(17, 34, 51));
      expect(
        edgeColor(rgba: bytes, width: 1, height: 1),
        const RgbColor(17, 34, 51),
      );
    });

    test('尺寸不合法 / 缓冲太短返回 null，不抛异常', () {
      expect(edgeColor(rgba: Uint8List(0), width: 0, height: 0), isNull);
      expect(edgeColor(rgba: Uint8List(8), width: 4, height: 4), isNull);
    });

    test('band 比图还大时夹到半边长，不会死循环也不会漏掉像素', () {
      final bytes = rgbaImage(5, 5, (int x, int y) => solid(10, 20, 30));
      expect(
        edgeColor(rgba: bytes, width: 5, height: 5, band: 99),
        const RgbColor(10, 20, 30),
      );
    });
  });

  group('averageColors', () {
    test('双页取平均；空值跳过；全空返回 null', () {
      expect(
        averageColors(const <RgbColor?>[
          RgbColor(0, 0, 0),
          RgbColor(100, 200, 300),
        ]),
        const RgbColor(50, 100, 150),
      );
      expect(
        averageColors(const <RgbColor?>[null, RgbColor(10, 20, 30)]),
        const RgbColor(10, 20, 30),
      );
      expect(averageColors(const <RgbColor?>[null, null]), isNull);
      expect(averageColors(const <RgbColor?>[]), isNull);
    });
  });

  group('RgbColor', () {
    test('亮度阈值：黑为暗、白为亮，相等与 hashCode 按分量', () {
      expect(const RgbColor(0, 0, 0).isDark, isTrue);
      expect(const RgbColor(255, 255, 255).isDark, isFalse);
      expect(const RgbColor(1, 2, 3), const RgbColor(1, 2, 3));
      expect(
        const RgbColor(1, 2, 3).hashCode,
        const RgbColor(1, 2, 3).hashCode,
      );
      expect(const RgbColor(1, 2, 3).toString(), contains('RgbColor'));
    });
  });
}
