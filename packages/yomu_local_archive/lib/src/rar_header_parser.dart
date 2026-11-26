import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/legacy_charset.dart';

/// 纯 Dart 解析出的 RAR 归档头摘要（用于快速探测加密/固实状态及无压缩 Stored 条目，LMB-12）。
final class RarHeaderProbe {
  const RarHeaderProbe({
    required this.magic,
    required this.isSolid,
    required this.isEncrypted,
    this.storedEntries = const <RarStoredEntry>[],
  });

  final ContainerMagic magic;
  final bool isSolid;
  final bool isEncrypted;
  final List<RarStoredEntry> storedEntries;
}

final class RarStoredEntry {
  const RarStoredEntry({
    required this.name,
    required this.dataOffset,
    required this.size,
  });

  final String name;
  final int dataOffset;
  final int size;
}

/// 零依赖探测 RAR4 / RAR5 二进制头，识别加密、固实标记并提取无压缩（Method 0x30 / 0）条目偏移。
RarHeaderProbe? inspectRarBytes(Uint8List bytes) {
  final magic = sniffContainerMagic(bytes);
  if (magic == ContainerMagic.rar4) {
    return _inspectRar4(bytes);
  }
  if (magic == ContainerMagic.rar5) {
    return _inspectRar5(bytes);
  }
  return null;
}

RarHeaderProbe _inspectRar4(Uint8List bytes) {
  final view = ByteData.sublistView(bytes);
  var pos = 7; // Skip Rar!\x1a\x07\x00
  var isSolid = false;
  var isEncrypted = false;
  final stored = <RarStoredEntry>[];

  while (pos + 7 <= bytes.length) {
    final headType = bytes[pos + 2];
    final headFlags = view.getUint16(pos + 3, Endian.little);
    final headSize = view.getUint16(pos + 5, Endian.little);
    if (headSize < 7 || pos + headSize > bytes.length) break;

    var addSize = 0;
    if ((headFlags & 0x8000) != 0 && pos + 11 <= bytes.length) {
      addSize = view.getUint32(pos + 7, Endian.little);
    }

    if (headType == 0x73) {
      // Main archive header (MHD)
      if ((headFlags & 0x0008) != 0) isSolid = true;
      if ((headFlags & 0x0080) != 0) isEncrypted = true; // MHD_PASSWORD
    } else if (headType == 0x74 && headSize >= 32) {
      // File header (FHD)
      if ((headFlags & 0x0004) != 0) isEncrypted = true; // FHD_PASSWORD
      if ((headFlags & 0x0010) != 0) isSolid = true; // FHD_SOLID
      final packSize = view.getUint32(pos + 7, Endian.little);
      final method = bytes[pos + 25];
      final nameSize = view.getUint16(pos + 26, Endian.little);
      addSize = packSize;
      final nameStart = pos + 32;
      if (nameStart + nameSize <= pos + headSize) {
        final nameBytes = Uint8List.sublistView(
          bytes,
          nameStart,
          nameStart + nameSize,
        );
        final isUtf8 = (headFlags & 0x0200) != 0;
        final name = decodeArchiveEntryName(nameBytes, isUtf8: isUtf8);
        final dataOffset = pos + headSize;
        // Method 0x30 ('0') = Stored (uncompressed)
        if (method == 0x30 &&
            !isEncrypted &&
            dataOffset + packSize <= bytes.length) {
          stored.add(
            RarStoredEntry(name: name, dataOffset: dataOffset, size: packSize),
          );
        }
      }
    } else if (headType == 0x7B) {
      break; // ENDARC
    }

    final next = pos + headSize + addSize;
    if (next <= pos) break;
    pos = next;
  }

  return RarHeaderProbe(
    magic: ContainerMagic.rar4,
    isSolid: isSolid,
    isEncrypted: isEncrypted,
    storedEntries: List<RarStoredEntry>.unmodifiable(stored),
  );
}

RarHeaderProbe _inspectRar5(Uint8List bytes) {
  var pos = 8; // Skip Rar!\x1a\x07\x01\x00
  var isSolid = false;
  var isEncrypted = false;

  while (pos + 6 <= bytes.length) {
    pos += 4; // Skip Header CRC32
    final hSize = _readVint(bytes, pos);
    if (hSize == null || hSize.value <= 0) break;
    final headerStart = hSize.nextOffset;
    final headerEnd = headerStart + hSize.value;
    if (headerEnd > bytes.length) break;

    var cur = headerStart;
    final hType = _readVint(bytes, cur);
    if (hType == null) break;
    cur = hType.nextOffset;
    final hFlags = _readVint(bytes, cur);
    if (hFlags == null) break;
    cur = hFlags.nextOffset;

    var dataSize = 0;
    if ((hFlags.value & 0x0001) != 0) {
      final extraSize = _readVint(bytes, cur);
      if (extraSize == null) break;
      cur = extraSize.nextOffset;
    }
    if ((hFlags.value & 0x0002) != 0) {
      final dSize = _readVint(bytes, cur);
      if (dSize == null) break;
      dataSize = dSize.value;
      cur = dSize.nextOffset;
    }

    if (hType.value == 1) {
      // Main archive header
      final archFlags = _readVint(bytes, cur);
      if (archFlags != null && (archFlags.value & 0x0004) != 0) {
        isSolid = true;
      }
    } else if (hType.value == 4) {
      // Archive encryption header
      isEncrypted = true;
      break;
    } else if (hType.value == 5) {
      break; // End of archive
    }

    final next = headerEnd + dataSize;
    if (next <= pos) break;
    pos = next;
  }

  return RarHeaderProbe(
    magic: ContainerMagic.rar5,
    isSolid: isSolid,
    isEncrypted: isEncrypted,
  );
}

({int value, int nextOffset})? _readVint(Uint8List bytes, int start) {
  var result = 0;
  var shift = 0;
  var i = start;
  while (i < bytes.length && shift <= 56) {
    final b = bytes[i++];
    result |= (b & 0x7F) << shift;
    if ((b & 0x80) == 0) {
      return (value: result, nextOffset: i);
    }
    shift += 7;
  }
  return null;
}
