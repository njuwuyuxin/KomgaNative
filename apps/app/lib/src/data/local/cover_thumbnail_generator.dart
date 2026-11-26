import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:yomu_domain/yomu_domain.dart';

/// 封面缩略图编码函数签名（单测可注入轻量实现）。
typedef CoverThumbnailEncoder = Future<Uint8List?> Function(
  Uint8List rawPageBytes, {
  required ReadingDirection direction,
});

const int _targetCoverWidth = 360;
const double _wideCoverAspectThreshold = 1.35;

/// 将漫画封面页压缩为轻量缩略图；若检测到连体宽封皮（封底+书脊+正封），按阅读方向自动裁取正封半幅。
Future<Uint8List?> encodeDefaultCoverThumbnail(
  Uint8List rawPageBytes, {
  required ReadingDirection direction,
}) async {
  if (rawPageBytes.isEmpty) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? decoded;
  ui.Image? cropped;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(rawPageBytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final rawW = descriptor.width;
    final rawH = descriptor.height;
    if (rawW <= 0 || rawH <= 0) return rawPageBytes;

    final isWideWraparound = (rawW / rawH) > _wideCoverAspectThreshold;
    final decodeTargetW = isWideWraparound
        ? (_targetCoverWidth * 2).clamp(1, rawW)
        : _targetCoverWidth.clamp(1, rawW);

    codec = await descriptor.instantiateCodec(targetWidth: decodeTargetW);
    final frame = await codec.getNextFrame();
    decoded = frame.image;

    if (!isWideWraparound) {
      final byteData = await decoded.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List() ?? rawPageBytes;
    }

    // 连体封皮（w/h > 1.35）：日漫 RTL 正封在右半幅（裁右侧 48% 避开书脊），其余正封在左半幅。
    final imgW = decoded.width.toDouble();
    final imgH = decoded.height.toDouble();
    final cropW = (imgW * 0.48).roundToDouble().clamp(1.0, imgW);
    final srcLeft = direction.isRightToLeft ? (imgW - cropW) : 0.0;
    final srcRect = ui.Rect.fromLTWH(srcLeft, 0, cropW, imgH);
    final dstRect = ui.Rect.fromLTWH(0, 0, cropW, imgH);

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(decoded, srcRect, dstRect, ui.Paint());
    final picture = recorder.endRecording();
    cropped = await picture.toImage(cropW.round(), imgH.round());
    picture.dispose();

    final outData = await cropped.toByteData(format: ui.ImageByteFormat.png);
    return outData?.buffer.asUint8List() ?? rawPageBytes;
  } on Object {
    // 无头单测中构造的最小头部假图片不含完整像素载荷：回退保存原始字节作为缩略图。
    return rawPageBytes;
  } finally {
    cropped?.dispose();
    decoded?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}
