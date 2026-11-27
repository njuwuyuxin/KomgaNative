import 'dart:convert';
import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/legacy_charset.dart';
import 'package:yomu_local_archive/src/zip_directory.dart';
import 'package:yomu_local_archive/src/zip_entry_extractor.dart';

/// 为中文/日文老压缩包生成多编码密码字节候选列表（LMB-13）。
///
/// Windows 中文/日文压缩软件（WinRAR / 7-Zip / Bandizip）常使用系统代码页（GBK / Shift-JIS）
/// 对 ZipCrypto 密码做字节哈希，而非 UTF-8。本函数自动按 `UTF-8 -> GBK -> Shift-JIS`
/// 去重展开候选字节序列，让用户输入一次中文密码即可自动兼容跨平台压缩包。
List<Uint8List> expandPasswordByteCandidates(String password) {
  final out = <Uint8List>[];
  void addUnique(Uint8List candidate) {
    for (final existing in out) {
      if (_bytesEqual(existing, candidate)) return;
    }
    out.add(candidate);
  }

  addUnique(Uint8List.fromList(utf8.encode(password)));
  final hasNonAscii = password.codeUnits.any((c) => c >= 0x80);
  if (hasNonAscii) {
    final gbk = encodeGbkBytes(password);
    if (gbk != null) addUnique(gbk);
    final sjis = encodeShiftJisBytes(password);
    if (sjis != null) addUnique(sjis);
  }
  return out;
}

/// 传统 PKWARE ZipCrypto 加密数据流解密器（兼容 Stored 与 Deflate）。
///
/// 校验 12 字节加密头的校验字节（`expectedCheckByte` 为 `crc32 >> 24`，若启用 Data Descriptor
/// 则为 `lastModTime >> 8`）；校验不通过返回 `null`（表示密码错误或编码不匹配）。
Uint8List? decryptZipCryptoPayload(
  Uint8List encryptedPayload, {
  required Uint8List passwordBytes,
  required int expectedCheckByte,
  int? altCheckByte,
}) {
  if (encryptedPayload.length < 12) return null;
  final keys = _ZipCryptoKeys(passwordBytes);

  var lastDecrypted = 0;
  for (var i = 0; i < 12; i++) {
    lastDecrypted = keys.decryptByte(encryptedPayload[i]);
  }
  final matchesPrimary = lastDecrypted == (expectedCheckByte & 0xFF);
  final matchesAlt =
      altCheckByte != null && lastDecrypted == (altCheckByte & 0xFF);
  if (!matchesPrimary && !matchesAlt) {
    return null;
  }

  final out = Uint8List(encryptedPayload.length - 12);
  for (var i = 12; i < encryptedPayload.length; i++) {
    out[i - 12] = keys.decryptByte(encryptedPayload[i]);
  }
  return out;
}

/// 传统 PKWARE ZipCrypto 加密器（主要用于单测构造真实加密 CBZ 夹具）。
Uint8List encryptZipCryptoPayload(
  Uint8List plainPayload, {
  required Uint8List passwordBytes,
  required int checkByte,
}) {
  final keys = _ZipCryptoKeys(passwordBytes);
  final out = Uint8List(plainPayload.length + 12);
  // 11 字节确定性盐 + 1 字节校验位
  for (var i = 0; i < 11; i++) {
    out[i] = keys.encryptByte((i * 37 + 13) & 0xFF);
  }
  out[11] = keys.encryptByte(checkByte & 0xFF);
  for (var i = 0; i < plainPayload.length; i++) {
    out[i + 12] = keys.encryptByte(plainPayload[i]);
  }
  return out;
}

/// 标准 IEEE 802.3 CRC-32 计算（供 ZipCrypto 密钥更新与校验使用）。
int computeCrc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc = _crc32Table[(crc ^ b) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// 尝试使用给定的单组密码字节解密并解压单个 ZIP 条目（校验头字节、解压体积上限与 CRC32，返回 `null` 表示密码错误）。
Uint8List? tryDecryptAndInflateZipEntry(
  Uint8List rawEncrypted,
  ZipEntryInfo entry,
  Uint8List passwordBytes, {
  int maxUncompressedBytes = kMaxZipEntryUncompressedBytes,
}) {
  validateZipEntrySizeBounds(entry, maxUncompressedBytes: maxUncompressedBytes);
  final primaryCheck = entry.hasDataDescriptor
      ? (entry.lastModTime >> 8) & 0xFF
      : (entry.crc32 >> 24) & 0xFF;
  final altCheck = entry.hasDataDescriptor
      ? (entry.crc32 >> 24) & 0xFF
      : (entry.lastModTime >> 8) & 0xFF;

  final decrypted = decryptZipCryptoPayload(
    rawEncrypted,
    passwordBytes: passwordBytes,
    expectedCheckByte: primaryCheck,
    altCheckByte: altCheck,
  );
  if (decrypted == null) return null;

  final Uint8List plain;
  if (entry.compressionMethod == 0) {
    if (decrypted.length > maxUncompressedBytes ||
        decrypted.length != entry.uncompressedSize) {
      return null;
    }
    plain = decrypted;
  } else if (entry.compressionMethod == 8) {
    try {
      plain = inflateRawDeflateBounded(
        decrypted,
        maxBytes: maxUncompressedBytes,
        expectedSize: entry.uncompressedSize,
      );
    } on ArchiveException {
      return null;
    }
  } else {
    throw ArchiveException(
      ArchiveErrorKind.unsupportedCompression,
      'Unsupported compression method ${entry.compressionMethod}',
    );
  }

  if (entry.crc32 != 0 && computeCrc32(plain) != (entry.crc32 & 0xFFFFFFFF)) {
    return null;
  }
  return plain;
}

/// 在多编码密码候选（UTF-8 / GBK / Shift-JIS）中探测正确解锁该条目的密码字节。
({Uint8List passwordBytes, Uint8List plainBytes})? probeZipCryptoPassword(
  Uint8List rawEncrypted,
  ZipEntryInfo entry,
  String password, {
  int maxUncompressedBytes = kMaxZipEntryUncompressedBytes,
}) {
  for (final candidate in expandPasswordByteCandidates(password)) {
    final plain = tryDecryptAndInflateZipEntry(
      rawEncrypted,
      entry,
      candidate,
      maxUncompressedBytes: maxUncompressedBytes,
    );
    if (plain != null) {
      return (passwordBytes: candidate, plainBytes: plain);
    }
  }
  return null;
}

final class _ZipCryptoKeys {
  _ZipCryptoKeys(Uint8List passwordBytes) {
    for (final b in passwordBytes) {
      _updateKeys(b);
    }
  }

  int _k0 = 0x12345678;
  int _k1 = 0x23456789;
  int _k2 = 0x34567890;

  int _streamByte() {
    final temp = (_k2 | 2) & 0xFFFF;
    return ((temp * (temp ^ 1)) >>> 8) & 0xFF;
  }

  int decryptByte(int cipherByte) {
    final plain = (cipherByte ^ _streamByte()) & 0xFF;
    _updateKeys(plain);
    return plain;
  }

  int encryptByte(int plainByte) {
    final cipher = (plainByte ^ _streamByte()) & 0xFF;
    _updateKeys(plainByte);
    return cipher;
  }

  void _updateKeys(int plainByte) {
    _k0 = _crc32Step(_k0, plainByte);
    _k1 = ((_k1 + (_k0 & 0xFF)) & 0xFFFFFFFF);
    _k1 = ((_k1 * 134775813 + 1) & 0xFFFFFFFF);
    _k2 = _crc32Step(_k2, (_k1 >>> 24) & 0xFF);
  }

  static int _crc32Step(int crc, int byte) =>
      _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
}

final Uint32List _crc32Table = _buildCrc32Table();

Uint32List _buildCrc32Table() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var j = 0; j < 8; j++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    table[i] = c & 0xFFFFFFFF;
  }
  return table;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
