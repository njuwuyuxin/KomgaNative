import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:komga_reader_engine/komga_reader_engine.dart';

/// 从页图字节里取"页边主色"（UI-P1-5 动态背景）。
///
/// 解码时就把宽度降到 [targetWidth]（默认 32）：提色只需要"页边大致是什么颜色"，
/// 按原图解码既慢又白占内存。真正的图像解码由 Flutter 引擎在后台线程完成，
/// 之后的取平均是 O(周长) 的整数运算（一千像素左右），
/// 再单开一个 isolate 反而多一次序列化开销——所以这一步是内联的。
///
/// 任何失败（坏图、不支持的格式）都返回 null：提色是装饰，
/// 绝不能因为一张图取色失败影响阅读。
Future<RgbColor?> pageEdgeColor(Uint8List bytes, {int targetWidth = 32}) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return edgeColor(
      rgba: data.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
  } on Object {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
