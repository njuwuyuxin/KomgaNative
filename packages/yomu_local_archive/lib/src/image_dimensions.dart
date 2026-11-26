import 'dart:typed_data';

/// 图像像素宽高。
typedef ImageSize = ({int width, int height});

/// 不解码整张位图，仅从图片文件头部字节嗅探精确像素宽高。
///
/// 支持 PNG、JPEG（含前置 EXIF/ICC 段）、WebP（VP8 / VP8L / VP8X）、GIF、BMP。
/// 无法识别或头部字节不足时返回 `null`（阅读器会在实际解码后回退测量）。
ImageSize? sniffImageDimensions(Uint8List bytes) {
  if (bytes.length < 10) return null;
  return _sniffPng(bytes) ??
      _sniffJpeg(bytes) ??
      _sniffWebp(bytes) ??
      _sniffGif(bytes) ??
      _sniffBmp(bytes);
}

ImageSize? _sniffPng(Uint8List b) {
  if (b.length < 24) return null;
  if (b[0] != 0x89 ||
      b[1] != 0x50 ||
      b[2] != 0x4E ||
      b[3] != 0x47 ||
      b[4] != 0x0D ||
      b[5] != 0x0A ||
      b[6] != 0x1A ||
      b[7] != 0x0A) {
    return null;
  }
  // IHDR chunk 紧跟 8 字节签名：4 字节长度 + 4 字节 'IHDR' + 4 字节宽 + 4 字节高。
  if (b[12] != 0x49 || b[13] != 0x48 || b[14] != 0x44 || b[15] != 0x52) {
    return null;
  }
  final view = ByteData.sublistView(b);
  final width = view.getUint32(16);
  final height = view.getUint32(20);
  return _validSize(width, height);
}

ImageSize? _sniffGif(Uint8List b) {
  if (b.length < 10) return null;
  if (b[0] != 0x47 || b[1] != 0x49 || b[2] != 0x46 || b[3] != 0x38) {
    return null;
  }
  if ((b[4] != 0x37 && b[4] != 0x39) || b[5] != 0x61) return null;
  final view = ByteData.sublistView(b);
  final width = view.getUint16(6, Endian.little);
  final height = view.getUint16(8, Endian.little);
  return _validSize(width, height);
}

ImageSize? _sniffBmp(Uint8List b) {
  if (b.length < 26) return null;
  if (b[0] != 0x42 || b[1] != 0x4D) return null;
  final view = ByteData.sublistView(b);
  final dibSize = view.getUint32(14, Endian.little);
  if (dibSize < 12) return null;
  if (dibSize == 12) {
    final width = view.getUint16(18, Endian.little);
    final height = view.getUint16(20, Endian.little);
    return _validSize(width, height);
  }
  final width = view.getInt32(18, Endian.little);
  final height = view.getInt32(22, Endian.little).abs();
  return _validSize(width, height);
}

ImageSize? _sniffWebp(Uint8List b) {
  if (b.length < 30) return null;
  if (b[0] != 0x52 ||
      b[1] != 0x49 ||
      b[2] != 0x46 ||
      b[3] != 0x46 ||
      b[8] != 0x57 ||
      b[9] != 0x45 ||
      b[10] != 0x42 ||
      b[11] != 0x50) {
    return null;
  }
  // Chunk fourCC at 12..16
  if (b[12] != 0x56 || b[13] != 0x50 || b[14] != 0x38) return null;
  final kind = b[15];
  final view = ByteData.sublistView(b);

  // 'VP8 ' (lossy): 3-byte frame tag at 20..22, signature 9D 01 2A at 23..25
  if (kind == 0x20) {
    if (b[23] != 0x9D || b[24] != 0x01 || b[25] != 0x2A) return null;
    final width = view.getUint16(26, Endian.little) & 0x3FFF;
    final height = view.getUint16(28, Endian.little) & 0x3FFF;
    return _validSize(width, height);
  }

  // 'VP8L' (lossless): signature 0x2F at 20, packed 14-bit dims at 21..24
  if (kind == 0x4C) {
    if (b[20] != 0x2F) return null;
    final bits = view.getUint32(21, Endian.little);
    final width = (bits & 0x3FFF) + 1;
    final height = ((bits >> 14) & 0x3FFF) + 1;
    return _validSize(width, height);
  }

  // 'VP8X' (extended): 24-bit width-1 at 24..26, height-1 at 27..29
  if (kind == 0x58) {
    final width = (b[24] | (b[25] << 8) | (b[26] << 16)) + 1;
    final height = (b[27] | (b[28] << 8) | (b[29] << 16)) + 1;
    return _validSize(width, height);
  }

  return null;
}

ImageSize? _sniffJpeg(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var offset = 2;
  while (offset + 3 < b.length) {
    if (b[offset] != 0xFF) {
      offset++;
      continue;
    }
    // 跳过连续填充的 0xFF。
    while (offset < b.length && b[offset] == 0xFF) {
      offset++;
    }
    if (offset >= b.length) return null;
    final marker = b[offset++];

    // 无长度载荷的控制标记（SOI / EOI / TEM / RST0..RST7）。
    if (marker == 0x00 ||
        marker == 0x01 ||
        marker == 0xD8 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      continue;
    }
    if (marker == 0xD9 || marker == 0xDA) {
      // 到达 EOI 或 SOS 压缩图像流仍未见 SOF，停止扫描。
      return null;
    }
    if (offset + 1 >= b.length) return null;
    final segLen = (b[offset] << 8) | b[offset + 1];
    if (segLen < 2) return null;

    if (_isJpegSofMarker(marker)) {
      if (offset + 6 >= b.length) return null;
      final height = (b[offset + 3] << 8) | b[offset + 4];
      final width = (b[offset + 5] << 8) | b[offset + 6];
      return _validSize(width, height);
    }

    offset += segLen;
  }
  return null;
}

bool _isJpegSofMarker(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;

ImageSize? _validSize(int width, int height) =>
    (width > 0 && height > 0) ? (width: width, height: height) : null;
