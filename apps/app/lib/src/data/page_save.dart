import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:komga_reader_engine/komga_reader_engine.dart';

/// 待写入系统相册/图片目录的最终图片载荷。
class PreparedPageImage {
  const PreparedPageImage({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

/// 生成当前屏应当保存的图片字节与文件名：
/// - 只有 1 页（单页模式、纵向模式、双页单独封面/跨页宽图）时直接原样输出该页字节，
///   零重编码损耗并保留原始格式（PNG / JPEG / WebP / GIF / AVIF）；
/// - 有 2 页（双页并排跨页）时按传入的左右视觉顺序并发取图并横向无缝拼接成完整 PNG 大图。
Future<PreparedPageImage> prepareScreenImageForSave({
  required String bookId,
  required List<int> orderedPages,
  required Future<Uint8List> Function(int page) loadPage,
}) async {
  if (orderedPages.isEmpty) {
    throw ArgumentError.value(
      orderedPages,
      'orderedPages',
      'Must not be empty',
    );
  }
  if (orderedPages.length == 1) {
    final page = orderedPages.first;
    final bytes = await loadPage(page);
    final format = sniffImageFormat(bytes);
    return PreparedPageImage(
      bytes: bytes,
      fileName: formatSavedPageFileName(
        bookId: bookId,
        pages: orderedPages,
        extension: format.extension,
      ),
      mimeType: format.mimeType,
    );
  }

  final pair = orderedPages.sublist(0, 2);
  final loaded = await Future.wait<Uint8List>(<Future<Uint8List>>[
    loadPage(pair[0]),
    loadPage(pair[1]),
  ]);
  final stitched = await stitchSideBySidePng(loaded[0], loaded[1]);
  return PreparedPageImage(
    bytes: stitched,
    fileName: formatSavedPageFileName(
      bookId: bookId,
      pages: pair,
      extension: ImageFileFormat.png.extension,
    ),
    mimeType: ImageFileFormat.png.mimeType,
  );
}

/// 将左、右两幅页面字节解码并按原始分辨率无缝横向拼接为单张 PNG。
Future<Uint8List> stitchSideBySidePng(
  Uint8List leftBytes,
  Uint8List rightBytes,
) async {
  ui.Image? leftImage;
  ui.Image? rightImage;
  ui.Picture? picture;
  ui.Image? combined;
  try {
    leftImage = await _decodeFullImage(leftBytes);
    rightImage = await _decodeFullImage(rightBytes);
    final plan = computeStitchLayout(
      leftWidth: leftImage.width,
      leftHeight: leftImage.height,
      rightWidth: rightImage.width,
      rightHeight: rightImage.height,
    );
    if (plan.isEmpty) {
      throw const FormatException('Invalid page image dimensions');
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()
      ..isAntiAlias = false
      ..filterQuality = ui.FilterQuality.high;
    canvas.drawImageRect(
      leftImage,
      ui.Rect.fromLTWH(
        0,
        0,
        leftImage.width.toDouble(),
        leftImage.height.toDouble(),
      ),
      ui.Rect.fromLTWH(
        plan.left.left,
        plan.left.top,
        plan.left.width,
        plan.left.height,
      ),
      paint,
    );
    canvas.drawImageRect(
      rightImage,
      ui.Rect.fromLTWH(
        0,
        0,
        rightImage.width.toDouble(),
        rightImage.height.toDouble(),
      ),
      ui.Rect.fromLTWH(
        plan.right.left,
        plan.right.top,
        plan.right.width,
        plan.right.height,
      ),
      paint,
    );
    picture = recorder.endRecording();
    combined = await picture.toImage(plan.width, plan.height);
    final data = await combined.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw const FormatException('Failed to encode stitched PNG');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    combined?.dispose();
    picture?.dispose();
    rightImage?.dispose();
    leftImage?.dispose();
  }
}

Future<ui.Image> _decodeFullImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}
