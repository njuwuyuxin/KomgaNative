import 'dart:io';
import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/archive_isolate.dart';
import 'package:yomu_local_archive/src/byte_source.dart';
import 'package:yomu_local_archive/src/image_dimensions.dart';
import 'package:yomu_local_archive/src/zip_crypto.dart';
import 'package:yomu_local_archive/src/zip_directory.dart';

const int _localFileHeaderSignature = 0x04034b50;
const int _maxHeaderSniffBytes = 32768;

/// 定位 ZIP 局部文件头后的真实压缩载荷偏移。
Future<int> resolveZipEntryDataOffset(
  RandomAccessByteSource source,
  int localHeaderOffset, {
  bool allowEncrypted = false,
}) async {
  final header = await source.readRange(localHeaderOffset, 30);
  if (header.length < 30) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Truncated local file header',
    );
  }
  final view = ByteData.sublistView(header);
  if (view.getUint32(0, Endian.little) != _localFileHeaderSignature) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Invalid local file header signature',
    );
  }
  final gpFlag = view.getUint16(6, Endian.little);
  if ((gpFlag & 0x0001) != 0 && !allowEncrypted) {
    throw const ArchiveException(ArchiveErrorKind.encryptedArchive);
  }
  final nameLen = view.getUint16(26, Endian.little);
  final extraLen = view.getUint16(28, Endian.little);
  return localHeaderOffset + 30 + nameLen + extraLen;
}

/// 按需读取、解密（若加密）并解压单个 ZIP 条目。
Future<Uint8List> extractZipEntryBytes(
  RandomAccessByteSource source,
  ZipEntryInfo entry, {
  Uint8List? passwordBytes,
}) async {
  final dataOffset = await resolveZipEntryDataOffset(
    source,
    entry.localHeaderOffset,
    allowEncrypted: entry.isEncrypted && passwordBytes != null,
  );
  final raw = await source.readRange(dataOffset, entry.compressedSize);
  if (raw.length < entry.compressedSize) {
    throw ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Truncated entry payload for ${entry.name}',
    );
  }
  if (entry.isEncrypted) {
    if (passwordBytes == null) {
      throw ArchiveException(ArchiveErrorKind.encryptedArchive, entry.name);
    }
    final pwdCopy = Uint8List.fromList(passwordBytes);
    final plain = await offloadBytesParse<Uint8List?>(
      raw,
      (Uint8List bytes) => tryDecryptAndInflateZipEntry(bytes, entry, pwdCopy),
      thresholdBytes: kZipCryptoIsolateThreshold,
    );
    if (plain == null) {
      throw ArchiveException(ArchiveErrorKind.encryptedArchive, entry.name);
    }
    return plain;
  }
  switch (entry.compressionMethod) {
    case 0:
      return Uint8List.fromList(raw);
    case 8:
      return offloadBytesTransform(
        raw,
        _inflateRawDeflate,
        thresholdBytes: kZipInflateIsolateThreshold,
      );
    default:
      throw ArchiveException(
        ArchiveErrorKind.unsupportedCompression,
        'Unsupported compression method ${entry.compressionMethod}',
      );
  }
}

Uint8List _inflateRawDeflate(Uint8List raw) {
  try {
    final inflated = ZLibCodec(raw: true).decode(raw);
    return inflated is Uint8List ? inflated : Uint8List.fromList(inflated);
  } on FormatException catch (e) {
    throw ArchiveException(ArchiveErrorKind.corruptedArchive, e.message);
  } on IOException catch (e) {
    throw ArchiveException(ArchiveErrorKind.corruptedArchive, e.toString());
  }
}

/// 嗅探 ZIP 条目图片尺寸（Stored 明文条目仅读前 32KB 头，不整页解压）。
Future<ImageSize?> sniffZipEntryDimensions(
  RandomAccessByteSource source,
  ZipEntryInfo entry, {
  Uint8List? passwordBytes,
}) async {
  try {
    if (entry.compressionMethod == 0 && !entry.isEncrypted) {
      final dataOffset = await resolveZipEntryDataOffset(
        source,
        entry.localHeaderOffset,
      );
      final toRead = entry.uncompressedSize < _maxHeaderSniffBytes
          ? entry.uncompressedSize
          : _maxHeaderSniffBytes;
      final headerSlice = await source.readRange(dataOffset, toRead);
      return sniffImageDimensions(headerSlice);
    }
    final decoded = await extractZipEntryBytes(
      source,
      entry,
      passwordBytes: passwordBytes,
    );
    return sniffImageDimensions(decoded);
  } on Object {
    return null;
  }
}
