import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/archive_isolate.dart';
import 'package:yomu_local_archive/src/byte_source.dart';
import 'package:yomu_local_archive/src/legacy_charset.dart';

/// ZIP 中央目录中的单条文件索引元数据。
final class ZipEntryInfo {
  const ZipEntryInfo({
    required this.name,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.compressionMethod,
    required this.generalPurposeBitFlag,
    this.crc32 = 0,
    this.lastModTime = 0,
  });

  final String name;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final int compressionMethod;
  final int generalPurposeBitFlag;
  final int crc32;
  final int lastModTime;

  /// General Purpose Bit 0 表示条目启用了传统 PKWARE 或强加密。
  bool get isEncrypted => (generalPurposeBitFlag & 0x0001) != 0;

  /// Bit 3 表示校验字节取 `lastModTime >> 8`。
  bool get hasDataDescriptor => (generalPurposeBitFlag & 0x0008) != 0;

  bool get isDirectory => name.endsWith('/');
}

const int _eocdSignature = 0x06054b50;
const int _zip64LocatorSignature = 0x07064b50;
const int _zip64EocdSignature = 0x06064b50;
const int _centralFileHeaderSignature = 0x02014b50;
const int _maxEocdSearchWindow = 65557; // 22 字节固定头 + 65535 最大注释

/// 仅通过尾部随机读取解析 ZIP / CBZ 中央目录（兼容 ZIP64），不读取压缩包主体。
Future<List<ZipEntryInfo>> readZipCentralDirectory(
  RandomAccessByteSource source,
) async {
  final totalLength = await source.length();
  if (totalLength <= 0) {
    throw const ArchiveException(ArchiveErrorKind.emptyFile);
  }
  if (totalLength < 22) {
    final head = await source.readRange(0, totalLength);
    _checkMagicNotOtherFormat(head);
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'File smaller than minimum ZIP EOCD size',
    );
  }

  final head = await source.readRange(0, 16);
  _checkMagicNotOtherFormat(head);

  final tailSize = totalLength < _maxEocdSearchWindow
      ? totalLength
      : _maxEocdSearchWindow;
  final tailOffset = totalLength - tailSize;
  final tail = await source.readRange(tailOffset, tailSize);
  final eocdRelPos = _findEocdOffset(tail);
  if (eocdRelPos < 0) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Missing ZIP End of Central Directory signature',
    );
  }

  final tailView = ByteData.sublistView(tail);
  var cdSize = tailView.getUint32(eocdRelPos + 12, Endian.little);
  var cdOffset = tailView.getUint32(eocdRelPos + 16, Endian.little);

  // 检测 ZIP64 EOCD Locator（紧挨标准 EOCD 前方 20 字节）。
  if (cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
    final zip64Bounds = await _readZip64Bounds(
      source,
      eocdAbsoluteOffset: tailOffset + eocdRelPos,
    );
    cdSize = zip64Bounds.cdSize;
    cdOffset = zip64Bounds.cdOffset;
  }

  if (cdSize == 0) return const <ZipEntryInfo>[];
  if (cdOffset < 0 || cdSize < 0 || cdOffset + cdSize > totalLength) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Central directory bounds exceed archive length',
    );
  }

  final cdBytes = await source.readRange(cdOffset, cdSize);
  if (cdBytes.length < cdSize) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Truncated central directory',
    );
  }
  return offloadBytesParse<List<ZipEntryInfo>>(
    cdBytes,
    _parseCentralDirectoryEntries,
    thresholdBytes: kCentralDirectoryIsolateThreshold,
  );
}

void _checkMagicNotOtherFormat(Uint8List head) {
  final magic = sniffContainerMagic(head);
  switch (magic) {
    case ContainerMagic.rar4 ||
        ContainerMagic.rar5 ||
        ContainerMagic.sevenZip ||
        ContainerMagic.pdf:
      throw ArchiveException.unsupportedContainer(magic);
    case ContainerMagic.zip || ContainerMagic.tar || ContainerMagic.unknown:
      return;
  }
}

int _findEocdOffset(Uint8List tail) {
  final view = ByteData.sublistView(tail);
  for (var pos = tail.length - 22; pos >= 0; pos--) {
    if (view.getUint32(pos, Endian.little) == _eocdSignature) {
      final commentLen = view.getUint16(pos + 20, Endian.little);
      if (pos + 22 + commentLen <= tail.length) {
        return pos;
      }
    }
  }
  return -1;
}

Future<({int cdOffset, int cdSize})> _readZip64Bounds(
  RandomAccessByteSource source, {
  required int eocdAbsoluteOffset,
}) async {
  if (eocdAbsoluteOffset < 20) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Missing ZIP64 locator',
    );
  }
  final locator = await source.readRange(eocdAbsoluteOffset - 20, 20);
  final locView = ByteData.sublistView(locator);
  if (locView.getUint32(0, Endian.little) != _zip64LocatorSignature) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Invalid ZIP64 locator signature',
    );
  }
  final zip64EocdOffset = locView.getUint64(8, Endian.little);
  final record = await source.readRange(zip64EocdOffset, 56);
  if (record.length < 56) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Truncated ZIP64 EOCD record',
    );
  }
  final recView = ByteData.sublistView(record);
  if (recView.getUint32(0, Endian.little) != _zip64EocdSignature) {
    throw const ArchiveException(
      ArchiveErrorKind.corruptedArchive,
      'Invalid ZIP64 EOCD signature',
    );
  }
  final cdSize = recView.getUint64(40, Endian.little);
  final cdOffset = recView.getUint64(48, Endian.little);
  return (cdOffset: cdOffset, cdSize: cdSize);
}

List<ZipEntryInfo> _parseCentralDirectoryEntries(Uint8List cdBytes) {
  final view = ByteData.sublistView(cdBytes);
  final entries = <ZipEntryInfo>[];
  var pos = 0;

  while (pos < cdBytes.length) {
    if (pos + 46 > cdBytes.length) {
      throw const ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Truncated central directory file header',
      );
    }
    final sig = view.getUint32(pos, Endian.little);
    if (sig != _centralFileHeaderSignature) {
      throw const ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Invalid central directory header signature',
      );
    }

    final gpFlag = view.getUint16(pos + 8, Endian.little);
    final method = view.getUint16(pos + 10, Endian.little);
    final lastModTime = view.getUint16(pos + 12, Endian.little);
    final crc32 = view.getUint32(pos + 16, Endian.little);
    var compSize = view.getUint32(pos + 20, Endian.little);
    var uncompSize = view.getUint32(pos + 24, Endian.little);
    final nameLen = view.getUint16(pos + 28, Endian.little);
    final extraLen = view.getUint16(pos + 30, Endian.little);
    final commentLen = view.getUint16(pos + 32, Endian.little);
    var localOffset = view.getUint32(pos + 42, Endian.little);

    final headerEnd = pos + 46 + nameLen + extraLen + commentLen;
    if (headerEnd > cdBytes.length) {
      throw const ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Central directory entry overflows buffer',
      );
    }

    final nameBytes = Uint8List.sublistView(
      cdBytes,
      pos + 46,
      pos + 46 + nameLen,
    );
    final name = _decodeEntryName(nameBytes, isUtf8: (gpFlag & 0x0800) != 0);

    if (extraLen > 0 &&
        (uncompSize == 0xFFFFFFFF ||
            compSize == 0xFFFFFFFF ||
            localOffset == 0xFFFFFFFF)) {
      final extra = Uint8List.sublistView(
        cdBytes,
        pos + 46 + nameLen,
        pos + 46 + nameLen + extraLen,
      );
      final z64 = _parseZip64Extra(
        extra,
        needUncomp: uncompSize == 0xFFFFFFFF,
        needComp: compSize == 0xFFFFFFFF,
        needOffset: localOffset == 0xFFFFFFFF,
      );
      if (z64.uncompSize != null) uncompSize = z64.uncompSize!;
      if (z64.compSize != null) compSize = z64.compSize!;
      if (z64.localOffset != null) localOffset = z64.localOffset!;
    }

    entries.add(
      ZipEntryInfo(
        name: name,
        compressedSize: compSize,
        uncompressedSize: uncompSize,
        localHeaderOffset: localOffset,
        compressionMethod: method,
        generalPurposeBitFlag: gpFlag,
        crc32: crc32,
        lastModTime: lastModTime,
      ),
    );
    pos = headerEnd;
  }

  return entries;
}

String _decodeEntryName(Uint8List bytes, {required bool isUtf8}) =>
    decodeArchiveEntryName(bytes, isUtf8: isUtf8);

({int? uncompSize, int? compSize, int? localOffset}) _parseZip64Extra(
  Uint8List extra, {
  required bool needUncomp,
  required bool needComp,
  required bool needOffset,
}) {
  final view = ByteData.sublistView(extra);
  var p = 0;
  while (p + 4 <= extra.length) {
    final headerId = view.getUint16(p, Endian.little);
    final dataSize = view.getUint16(p + 2, Endian.little);
    if (p + 4 + dataSize > extra.length) break;
    if (headerId == 0x0001) {
      var q = p + 4;
      final end = p + 4 + dataSize;
      int? uncomp;
      int? comp;
      int? offset;
      if (needUncomp && q + 8 <= end) {
        uncomp = view.getUint64(q, Endian.little);
        q += 8;
      }
      if (needComp && q + 8 <= end) {
        comp = view.getUint64(q, Endian.little);
        q += 8;
      }
      if (needOffset && q + 8 <= end) {
        offset = view.getUint64(q, Endian.little);
      }
      return (uncompSize: uncomp, compSize: comp, localOffset: offset);
    }
    p += 4 + dataSize;
  }
  return (uncompSize: null, compSize: null, localOffset: null);
}
