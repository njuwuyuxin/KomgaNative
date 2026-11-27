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
const int _inflateInputChunkBytes = 8 * 1024;
const int _compressedOverheadMargin = 64 * 1024;

/// 单个 ZIP 条目解压输出硬上限（128 MiB），防止压缩炸弹撑爆进程内存（OOM）。
const int kMaxZipEntryUncompressedBytes = 128 * 1024 * 1024;

/// 嵌套漫画合集包内单个子归档条目解压上限（512 MiB）。
const int kMaxNestedZipEntryBytes = 512 * 1024 * 1024;

/// 校验 ZIP 条目声明的压缩/解压体积是否在安全区间内（先于读盘与分配内存）。
void validateZipEntrySizeBounds(
  ZipEntryInfo entry, {
  int maxUncompressedBytes = kMaxZipEntryUncompressedBytes,
}) {
  if (entry.compressedSize < 0 || entry.uncompressedSize < 0) {
    throw ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Invalid negative entry size for ${entry.name}',
    );
  }
  if (entry.uncompressedSize > maxUncompressedBytes) {
    throw ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Entry ${entry.name} uncompressed size (${entry.uncompressedSize}) '
      'exceeds limit ($maxUncompressedBytes)',
    );
  }
  if (entry.compressedSize > maxUncompressedBytes + _compressedOverheadMargin) {
    throw ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Entry ${entry.name} compressed size (${entry.compressedSize}) '
      'exceeds limit ($maxUncompressedBytes)',
    );
  }
}

/// 定位 ZIP 局部文件头后的真实压缩载荷偏移。
Future<int> resolveZipEntryDataOffset(
  RandomAccessByteSource source,
  int localHeaderOffset, {
  bool allowEncrypted = false,
}) async {
  if (localHeaderOffset < 0) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Invalid negative local file header offset',
    );
  }
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

/// 按需读取、解密（若加密）并带输出上限解压单个 ZIP 条目。
Future<Uint8List> extractZipEntryBytes(
  RandomAccessByteSource source,
  ZipEntryInfo entry, {
  Uint8List? passwordBytes,
  int maxUncompressedBytes = kMaxZipEntryUncompressedBytes,
}) async {
  validateZipEntrySizeBounds(entry, maxUncompressedBytes: maxUncompressedBytes);
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
    final limit = maxUncompressedBytes;
    final plain = await offloadBytesParse<Uint8List?>(
      raw,
      (Uint8List bytes) => tryDecryptAndInflateZipEntry(
        bytes,
        entry,
        pwdCopy,
        maxUncompressedBytes: limit,
      ),
      thresholdBytes: kZipCryptoIsolateThreshold,
    );
    if (plain == null) {
      throw ArchiveException(ArchiveErrorKind.encryptedArchive, entry.name);
    }
    return plain;
  }
  switch (entry.compressionMethod) {
    case 0:
      if (raw.length != entry.uncompressedSize) {
        throw ArchiveException(
          ArchiveErrorKind.corruptedArchive,
          'Stored entry size mismatch for ${entry.name}: '
          'expected ${entry.uncompressedSize}, got ${raw.length}',
        );
      }
      return Uint8List.fromList(raw);
    case 8:
      final limit = maxUncompressedBytes;
      final expectedSize = entry.uncompressedSize;
      return offloadBytesTransform(
        raw,
        (Uint8List bytes) => inflateRawDeflateBounded(
          bytes,
          maxBytes: limit,
          expectedSize: expectedSize,
        ),
        thresholdBytes: kZipInflateIsolateThreshold,
      );
    default:
      throw ArchiveException(
        ArchiveErrorKind.unsupportedCompression,
        'Unsupported compression method ${entry.compressionMethod}',
      );
  }
}

/// 带流式输出上限与声明大小校验的 raw-Deflate 解压（防御压缩炸弹）。
///
/// 按 8 KB 输入切片喂入 `ZLibDecoder(raw: true)`，一旦累计输出字节超过
/// `min(maxBytes, expectedSize)` 立即中止并抛 [ArchiveException]，绝不把整颗炸弹展开到内存。
Uint8List inflateRawDeflateBounded(
  Uint8List raw, {
  int maxBytes = kMaxZipEntryUncompressedBytes,
  int? expectedSize,
}) {
  if (maxBytes < 0) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Invalid decompression size limit',
    );
  }
  if (expectedSize != null) {
    if (expectedSize < 0) {
      throw ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Invalid negative uncompressed size: $expectedSize',
      );
    }
    if (expectedSize > maxBytes) {
      throw ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Declared uncompressed size ($expectedSize) exceeds limit ($maxBytes)',
      );
    }
  }
  final effectiveLimit = expectedSize != null && expectedSize < maxBytes
      ? expectedSize
      : maxBytes;
  final collector = _BoundedBytesSink(effectiveLimit);
  final decoderSink = ZLibDecoder(raw: true).startChunkedConversion(collector);
  try {
    for (
      var offset = 0;
      offset < raw.length;
      offset += _inflateInputChunkBytes
    ) {
      final end = offset + _inflateInputChunkBytes < raw.length
          ? offset + _inflateInputChunkBytes
          : raw.length;
      decoderSink.add(Uint8List.sublistView(raw, offset, end));
    }
    decoderSink.close();
  } on ArchiveException {
    rethrow;
  } on FormatException catch (e) {
    throw ArchiveException(ArchiveErrorKind.corruptedArchive, e.message);
  } on IOException catch (e) {
    throw ArchiveException(ArchiveErrorKind.corruptedArchive, e.toString());
  }
  final output = collector.takeBytes();
  if (expectedSize != null && output.length != expectedSize) {
    throw ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Decompressed size mismatch: expected $expectedSize, got ${output.length}',
    );
  }
  return output;
}

final class _BoundedBytesSink implements Sink<List<int>> {
  _BoundedBytesSink(this._maxBytes);

  final int _maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  int _written = 0;

  @override
  void add(List<int> chunk) {
    _written += chunk.length;
    if (_written > _maxBytes) {
      throw ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Decompressed entry exceeds limit ($_maxBytes bytes)',
      );
    }
    _builder.add(chunk);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _builder.takeBytes();
}

/// 嗅探 ZIP 条目图片尺寸（Stored 明文条目仅读前 32KB 头，不整页解压）。
Future<ImageSize?> sniffZipEntryDimensions(
  RandomAccessByteSource source,
  ZipEntryInfo entry, {
  Uint8List? passwordBytes,
}) async {
  try {
    validateZipEntrySizeBounds(entry);
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
  } on ArchiveException {
    return null;
  }
}
