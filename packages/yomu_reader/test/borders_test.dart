import 'dart:typed_data';

import 'package:yomu_reader/yomu_reader.dart';
import 'package:test/test.dart';

Uint8List _rgba(
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

void main() {
  test('白边 + 黑正文：四边按比例裁掉', () {
    final bytes = _rgba(
      20,
      20,
      (int x, int y) => x < 4 || y < 4 || x >= 16 || y >= 16
          ? (r: 255, g: 255, b: 255, a: 255)
          : (r: 0, g: 0, b: 0, a: 255),
    );
    expect(
      detectBorderCrop(rgba: bytes, width: 20, height: 20),
      const BorderCrop(left: 0.2, top: 0.2, right: 0.2, bottom: 0.2),
    );
  });

  test('四边留白不对称，各边分别计算', () {
    final bytes = _rgba(
      20,
      20,
      (int x, int y) => x < 1 || x >= 17 || y < 2 || y >= 16
          ? (r: 255, g: 255, b: 255, a: 255)
          : (r: 0, g: 0, b: 0, a: 255),
    );
    expect(
      detectBorderCrop(rgba: bytes, width: 20, height: 20),
      const BorderCrop(left: 0.05, top: 0.1, right: 0.15, bottom: 0.2),
    );
  });

  test('黑边同样裁（扫描版黑边）', () {
    final bytes = _rgba(
      20,
      20,
      (int x, int y) => x < 4 || y < 4 || x >= 16 || y >= 16
          ? (r: 0, g: 0, b: 0, a: 255)
          : (r: 255, g: 255, b: 255, a: 255),
    );
    final crop = detectBorderCrop(rgba: bytes, width: 20, height: 20);
    expect(crop?.left, 0.2);
  });

  test('没有边框 / 整页纯色 / 四角不同 / 空图都不裁', () {
    final noBorder = _rgba(
      20,
      20,
      (int x, int y) => (r: 10, g: 20, b: 30, a: 255),
    );
    expect(
      detectBorderCrop(rgba: noBorder, width: 20, height: 20),
      BorderCrop.none,
    );

    final solid = _rgba(
      20,
      20,
      (int x, int y) => (r: 255, g: 255, b: 255, a: 255),
    );
    expect(
      detectBorderCrop(rgba: solid, width: 20, height: 20),
      BorderCrop.none,
    );

    final gradient = _rgba(
      20,
      20,
      (int x, int y) => (r: x * 12, g: y * 12, b: 0, a: 255),
    );
    expect(
      detectBorderCrop(rgba: gradient, width: 20, height: 20),
      BorderCrop.none,
    );

    expect(detectBorderCrop(rgba: Uint8List(0), width: 0, height: 0), isNull);
    expect(detectBorderCrop(rgba: Uint8List(4), width: 2, height: 2), isNull);
  });
}
