/// 最小几何类型，避免把 Flutter 的 `dart:ui` 引入纯逻辑包。
class SizeD {
  const SizeD(this.width, this.height);

  final double width;
  final double height;

  bool get isEmpty => width <= 0 || height <= 0;

  @override
  bool operator ==(Object other) =>
      other is SizeD && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() =>
      'SizeD(${width.toStringAsFixed(1)}, ${height.toStringAsFixed(1)})';
}

class RectD {
  const RectD(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  RectD translate(double dx, double dy) =>
      RectD(left + dx, top + dy, width, height);

  @override
  bool operator ==(Object other) =>
      other is RectD &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'RectD(${left.toStringAsFixed(1)}, ${top.toStringAsFixed(1)}, '
      '${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)})';
}
