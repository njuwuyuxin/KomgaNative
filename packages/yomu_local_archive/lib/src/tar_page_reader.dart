import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/archive_isolate.dart';
import 'package:yomu_local_archive/src/byte_source.dart';
import 'package:yomu_local_archive/src/chapter_extractor.dart';
import 'package:yomu_local_archive/src/comic_info_parser.dart';
import 'package:yomu_local_archive/src/image_dimensions.dart';
import 'package:yomu_local_archive/src/legacy_charset.dart';
import 'package:yomu_local_archive/src/natural_sort.dart';
import 'package:yomu_local_archive/src/zip_page_reader.dart';

const int _tarBlockSize = 512;
const int _tarHeaderSniffBytes = 32768;

/// 纯 Dart POSIX `ustar` / GNU `TAR`（`.cbt` / `.tar`）零全量解压偏移索引读取器（LMB-06）。
///
/// 仅顺序跳过 512 字节头记录每个图片载荷的 `(dataOffset, size)`；
/// 读页阶段直接 `source.readRange(localHeaderOffset, uncompressedSize)` 实现 \(O(1)\) 随机跳页。
final class TarComicReader implements ComicArchiveReader {
  TarComicReader._({
    required RandomAccessByteSource source,
    required List<ArchivePageEntry> pages,
    Uint8List? comicInfoBytes,
    List<ArchiveChapter> chapters = const <ArchiveChapter>[],
  }) : _source = source,
       pages = List<ArchivePageEntry>.unmodifiable(pages),
       comicInfoBytes = comicInfoBytes,
       chapters = List<ArchiveChapter>.unmodifiable(chapters);

  static Future<TarComicReader> open(
    RandomAccessByteSource source, {
    bool sniffDimensions = true,
  }) async {
    try {
      final totalLength = await source.length();
      if (totalLength <= 0) {
        throw const ArchiveException(ArchiveErrorKind.emptyFile);
      }
      if (totalLength < _tarBlockSize) {
        throw const ArchiveException(
          ArchiveErrorKind.corruptedArchive,
          'File smaller than TAR header block',
        );
      }

      final ({List<ArchivePageEntry> pages, Uint8List? comicInfoBytes}) scanned;
      if (source is FileByteSource && totalLength >= kTarScanIsolateThreshold) {
        // RandomAccessFile 句柄不可跨 Isolate 传输，因此在长驻工作线程按只读路径完成顺序头扫描后立即关闭句柄。
        final path = source.filePath;
        scanned = await offloadArchiveTask(() async {
          final bgSource = await FileByteSource.open(File(path));
          try {
            return await _scanTarArchive(
              bgSource,
              totalLength: totalLength,
              sniffDimensions: sniffDimensions,
            );
          } finally {
            await bgSource.close();
          }
        });
      } else {
        scanned = await _scanTarArchive(
          source,
          totalLength: totalLength,
          sniffDimensions: sniffDimensions,
        );
      }

      return TarComicReader._(
        source: source,
        pages: scanned.pages,
        comicInfoBytes: scanned.comicInfoBytes,
        chapters: resolveArchiveChapters(
          pages: scanned.pages,
          comicInfoBytes: scanned.comicInfoBytes,
        ),
      );
    } on Object {
      await source.close();
      rethrow;
    }
  }

  static Future<({List<ArchivePageEntry> pages, Uint8List? comicInfoBytes})>
  _scanTarArchive(
    RandomAccessByteSource source, {
    required int totalLength,
    required bool sniffDimensions,
  }) async {
    final imageEntries = <({String name, int dataOffset, int size})>[];
    ({int dataOffset, int size})? comicInfoLoc;

    var offset = 0;
    String? pendingLongName;
    String? pendingPaxPath;
    var parsedAnyHeader = false;

    while (offset + _tarBlockSize <= totalLength) {
      final header = await source.readRange(offset, _tarBlockSize);
      if (_isAllZero(header)) break;

      if (!_verifyTarChecksum(header)) {
        if (!parsedAnyHeader) {
          throw const ArchiveException(
            ArchiveErrorKind.corruptedArchive,
            'Invalid TAR header checksum',
          );
        }
        break;
      }
      parsedAnyHeader = true;

      final size = _parseTarSize(header);
      final typeFlag = header[156];
      final dataOffset = offset + _tarBlockSize;
      final paddedSize = (size + _tarBlockSize - 1) & ~(_tarBlockSize - 1);
      final nextOffset = dataOffset + paddedSize;

      if (size < 0 || dataOffset + size > totalLength) {
        throw const ArchiveException(
          ArchiveErrorKind.corruptedArchive,
          'TAR entry payload exceeds archive length',
        );
      }

      if (typeFlag == 0x4C) {
        final rawName = await source.readRange(dataOffset, size);
        pendingLongName = _decodeTarRawString(rawName);
        offset = nextOffset;
        continue;
      }
      if (typeFlag == 0x78) {
        final paxBytes = await source.readRange(dataOffset, size);
        pendingPaxPath = _parsePaxPath(paxBytes);
        offset = nextOffset;
        continue;
      }

      final name = pendingPaxPath ?? pendingLongName ?? _readUstarName(header);
      pendingLongName = null;
      pendingPaxPath = null;

      final isRegularFile = typeFlag == 0 || typeFlag == 0x30;
      if (isRegularFile && name.isNotEmpty) {
        final norm = name.replaceAll(r'\', '/');
        final lowerBase = norm.split('/').last.toLowerCase();
        if (lowerBase == 'comicinfo.xml' &&
            !norm.startsWith('__MACOSX/') &&
            comicInfoLoc == null) {
          comicInfoLoc = (dataOffset: dataOffset, size: size);
        } else if (isSupportedComicImagePath(norm)) {
          imageEntries.add((name: norm, dataOffset: dataOffset, size: size));
        }
      }
      offset = nextOffset;
    }

    if (imageEntries.isEmpty) {
      throw const ArchiveException(ArchiveErrorKind.noImages);
    }

    imageEntries.sort((a, b) => naturalCompare(a.name, b.name));

    Uint8List? comicInfoBytes;
    if (comicInfoLoc != null && comicInfoLoc.size > 0) {
      comicInfoBytes = await source.readRange(
        comicInfoLoc.dataOffset,
        comicInfoLoc.size,
      );
    }

    final pages = <ArchivePageEntry>[];
    for (var i = 0; i < imageEntries.length; i++) {
      final item = imageEntries[i];
      ImageSize? dims;
      if (sniffDimensions && item.size > 0) {
        final toRead = item.size < _tarHeaderSniffBytes
            ? item.size
            : _tarHeaderSniffBytes;
        final slice = await source.readRange(item.dataOffset, toRead);
        dims = sniffImageDimensions(slice);
      }
      pages.add(
        ArchivePageEntry(
          number: i + 1,
          entryName: item.name,
          uncompressedSize: item.size,
          compressedSize: item.size,
          localHeaderOffset: item.dataOffset,
          compressionMethod: 0,
          width: dims?.width,
          height: dims?.height,
          mediaType: mediaTypeForPath(item.name),
        ),
      );
    }
    return (pages: pages, comicInfoBytes: comicInfoBytes);
  }

  /// 利用数据库已缓存的页偏移索引直接构造（O(1) 零扫描直开）。
  factory TarComicReader.fromIndexedPages(
    RandomAccessByteSource source,
    List<ArchivePageEntry> indexedPages,
  ) {
    return TarComicReader._(source: source, pages: indexedPages);
  }

  final RandomAccessByteSource _source;

  @override
  final List<ArchivePageEntry> pages;

  @override
  final Uint8List? comicInfoBytes;

  @override
  ComicInfoMetadata? get embeddedMetadata => null;

  @override
  final List<ArchiveChapter> chapters;

  @override
  Future<Uint8List> readPage(int pageNumber) async {
    if (pageNumber < 1 || pageNumber > pages.length) {
      throw ArchiveException(
        ArchiveErrorKind.pageOutOfRange,
        'Page $pageNumber out of 1..${pages.length}',
      );
    }
    final entry = pages[pageNumber - 1];
    final bytes = await _source.readRange(
      entry.localHeaderOffset,
      entry.uncompressedSize,
    );
    if (bytes.length < entry.uncompressedSize) {
      throw const ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Truncated TAR page payload',
      );
    }
    return bytes;
  }

  @override
  Future<Uint8List?> readCoverImage() async => null;

  @override
  Future<void> close() => _source.close();
}

bool _isAllZero(Uint8List block) {
  for (final b in block) {
    if (b != 0) return false;
  }
  return true;
}

bool _verifyTarChecksum(Uint8List header) {
  final expected = _parseOctalField(header, 148, 8);
  if (expected == null) return false;
  var unsignedSum = 0;
  var signedSum = 0;
  for (var i = 0; i < _tarBlockSize; i++) {
    final byte = (i >= 148 && i < 156) ? 0x20 : header[i];
    unsignedSum += byte;
    signedSum += byte > 127 ? byte - 256 : byte;
  }
  return expected == unsignedSum || expected == signedSum;
}

int _parseTarSize(Uint8List header) {
  // GNU base-256 扩展大文件尺寸（最高位 0x80 置位）
  if ((header[124] & 0x80) != 0) {
    var value = 0;
    for (var i = 125; i < 136; i++) {
      value = (value << 8) | header[i];
    }
    return value;
  }
  return _parseOctalField(header, 124, 12) ?? -1;
}

int? _parseOctalField(Uint8List block, int start, int length) {
  final end = start + length;
  var i = start;
  while (i < end && (block[i] == 0x20 || block[i] == 0x00)) {
    i++;
  }
  var value = 0;
  var foundDigit = false;
  while (i < end) {
    final b = block[i];
    if (b == 0x00 || b == 0x20) break;
    if (b < 0x30 || b > 0x37) return null;
    value = (value << 3) | (b - 0x30);
    foundDigit = true;
    i++;
  }
  return foundDigit ? value : 0;
}

String _readUstarName(Uint8List header) {
  final name = _decodeTarRawString(Uint8List.sublistView(header, 0, 100));
  final prefix = _decodeTarRawString(Uint8List.sublistView(header, 345, 500));
  if (prefix.isEmpty) return name;
  return '$prefix/$name';
}

String _decodeTarRawString(Uint8List slice) {
  var end = slice.length;
  for (var i = 0; i < slice.length; i++) {
    if (slice[i] == 0) {
      end = i;
      break;
    }
  }
  if (end == 0) return '';
  return decodeArchiveEntryName(
    Uint8List.sublistView(slice, 0, end),
    isUtf8: false,
  ).trim();
}

String? _parsePaxPath(Uint8List paxBytes) {
  final text = utf8.decode(paxBytes, allowMalformed: true);
  for (final line in text.split('\n')) {
    final space = line.indexOf(' ');
    if (space < 0) continue;
    final kv = line.substring(space + 1);
    if (kv.startsWith('path=')) {
      final path = kv.substring(5).trim();
      if (path.isNotEmpty) return path;
    }
  }
  return null;
}
