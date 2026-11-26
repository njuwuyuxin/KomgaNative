import 'dart:typed_data';

/// 通过文件头魔数（Magic Bytes）识别出的真实容器格式。
///
/// 民间漫画资源常出现伪后缀（例如把 ZIP 压缩包命名为 `.cbr`），
/// 读取前先嗅探前 16 字节以真实二进制签名判定。
enum ContainerMagic { zip, rar4, rar5, sevenZip, pdf, unknown }

/// 本地归档解析失败的结构化原因。
enum ArchiveErrorKind {
  /// 空文件（0 字节）。
  emptyFile,

  /// 识别出是 RAR / 7z / PDF 等当前纯 ZIP 读取器不支持的容器。
  unsupportedContainer,

  /// 文件截断、签名错乱或中央目录损坏。
  corruptedArchive,

  /// 压缩包带密码加密。
  encryptedArchive,

  /// 使用了非 Stored(0) / Deflate(8) 的冷门压缩算法（如 BZip2 / LZMA）。
  unsupportedCompression,

  /// 归档合法，但内部没有任何受支持的漫画图片页。
  noImages,

  /// 检测到纯文字流式电子书 EPUB（非漫画/画集），按产品边界明确提示用户。
  textOnlyEpub,

  /// 请求的 1 基页码越界。
  pageOutOfRange,

  /// 底层文件不存在、权限丢失或磁盘读取失败。
  ioError,
}

/// 本地归档引擎统一抛出的密封异常。
final class ArchiveException implements Exception {
  const ArchiveException(this.kind, [this.detail]) : detectedMagic = null;

  const ArchiveException.unsupportedContainer(
    ContainerMagic this.detectedMagic, [
    this.detail,
  ]) : kind = ArchiveErrorKind.unsupportedContainer;

  final ArchiveErrorKind kind;
  final String? detail;

  /// 若 [kind] 为 [ArchiveErrorKind.unsupportedContainer]，给出识别到的真实容器类型。
  final ContainerMagic? detectedMagic;

  @override
  String toString() => detail == null
      ? 'ArchiveException(${kind.name})'
      : 'ArchiveException(${kind.name}: $detail)';
}

/// 读取文件起始字节（建议 ≥ 8 字节）嗅探真实容器类型。
ContainerMagic sniffContainerMagic(Uint8List header) {
  if (header.length >= 4 &&
      header[0] == 0x50 &&
      header[1] == 0x4B &&
      ((header[2] == 0x03 && header[3] == 0x04) ||
          (header[2] == 0x05 && header[3] == 0x06) ||
          (header[2] == 0x07 && header[3] == 0x08))) {
    return ContainerMagic.zip;
  }

  if (header.length >= 8 &&
      header[0] == 0x52 &&
      header[1] == 0x61 &&
      header[2] == 0x72 &&
      header[3] == 0x21 &&
      header[4] == 0x1A &&
      header[5] == 0x07) {
    if (header[6] == 0x01 && header[7] == 0x00) return ContainerMagic.rar5;
    if (header[6] == 0x00) return ContainerMagic.rar4;
  }

  if (header.length >= 6 &&
      header[0] == 0x37 &&
      header[1] == 0x7A &&
      header[2] == 0xBC &&
      header[3] == 0xAF &&
      header[4] == 0x27 &&
      header[5] == 0x1C) {
    return ContainerMagic.sevenZip;
  }

  if (header.length >= 4 &&
      header[0] == 0x25 &&
      header[1] == 0x50 &&
      header[2] == 0x44 &&
      header[3] == 0x46) {
    return ContainerMagic.pdf;
  }

  return ContainerMagic.unknown;
}
