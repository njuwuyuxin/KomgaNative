import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yomu_reader/yomu_reader.dart';

/// 从页图字节检测四周纯色边框（UI-P3-10）。
///
/// 解码到 48px 宽：边框检测只需要"这一行是不是同一种颜色"，原图尺寸既慢又
/// 白占内存。失败返回 null（调用方按"不裁"处理），装饰性处理不能影响阅读。
Future<BorderCrop?> pageBorderCrop(
  Uint8List bytes, {
  int targetWidth = 48,
}) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return detectBorderCrop(
      rgba: data.buffer.asUint8List(),
      width: image.width,
      height: image.height,
    );
  } on Exception {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
