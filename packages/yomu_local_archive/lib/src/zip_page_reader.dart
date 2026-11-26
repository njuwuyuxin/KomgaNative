import 'dart:io';
import 'dart:typed_data';

import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/byte_source.dart';
import 'package:yomu_local_archive/src/chapter_extractor.dart';
import 'package:yomu_local_archive/src/comic_info_parser.dart';
import 'package:yomu_local_archive/src/image_dimensions.dart';
import 'package:yomu_local_archive/src/natural_sort.dart';
import 'package:yomu_local_archive/src/zip_directory.dart';

/// 本地归档或文件夹中的单页索引信息（1 基页码，可直接持久化至本地页索引表）。
final class ArchivePageEntry {
  const ArchivePageEntry({
    required this.number,
    required this.entryName,
    required this.uncompressedSize,
    this.compressedSize = 0,
    this.localHeaderOffset = 0,
    this.compressionMethod = 0,
    this.width,
    this.height,
    this.mediaType,
  });

  /// 1 基页码。
  final int number;
  final String entryName;
  final int uncompressedSize;
  final int compressedSize;
  final int localHeaderOffset;
  final int compressionMethod;
  final int? width;
  final int? height;
  final String? mediaType;

  PageInfo toPageInfo() => PageInfo(
    number: number,
    width: width,
    height: height,
    mediaType: mediaType,
    sizeBytes: uncompressedSize,
  );
}

/// 统一的本地漫画容器读取接口（屏蔽 ZIP/CBZ、漫画 EPUB 与图片文件夹差异）。
abstract interface class ComicArchiveReader {
  List<ArchivePageEntry> get pages;

  /// 若归档根目录或子目录存在 `ComicInfo.xml`，返回其原始字节；否则为 `null`。
  Uint8List? get comicInfoBytes;

  /// 容器自携带的结构化元数据（如 EPUB `content.opf` 解析结果）；未提供时返回 `null`。
  ComicInfoMetadata? get embeddedMetadata;

  /// 单本书内部章节目录（如 EPUB TOC、子文件夹起始页、`ComicInfo.xml` 书签）。
  List<ArchiveChapter> get chapters;

  /// 按 1 基页码按需读取并解压单页图片字节。
  Future<Uint8List> readPage(int pageNumber);

  Future<void> close();
}

const int _localFileHeaderSignature = 0x04034b50;

/// Stored 条目嗅探图片头的最大读取字节数（足以跨越常见 JPEG EXIF APP1 段）。
const int _maxHeaderSniffBytes = 32768;

/// 基于中央目录偏移的 \(O(1)\) 随机访问 ZIP / CBZ 漫画读取器。
final class ZipComicReader implements ComicArchiveReader {
  ZipComicReader._({
    required RandomAccessByteSource source,
    required List<ArchivePageEntry> pages,
    Uint8List? comicInfoBytes,
    List<ArchiveChapter> chapters = const <ArchiveChapter>[],
  }) : _source = source,
       pages = List<ArchivePageEntry>.unmodifiable(pages),
       comicInfoBytes = comicInfoBytes,
       chapters = List<ArchiveChapter>.unmodifiable(chapters);

  /// 扫描中央目录建立页表、提取 `ComicInfo.xml`，并可选嗅探每页宽高（导入阶段调用）。
  static Future<ZipComicReader> open(
    RandomAccessByteSource source, {
    bool sniffDimensions = true,
  }) async {
    try {
      final entries = await readZipCentralDirectory(source);
      return await openWithEntries(
        source,
        entries,
        sniffDimensions: sniffDimensions,
      );
    } on Object {
      await source.close();
      rethrow;
    }
  }

  /// 复用已读取的中央目录条目构造 ZIP 读取器（供统一容器探测入口避免二次读 EOCD）。
  static Future<ZipComicReader> openWithEntries(
    RandomAccessByteSource source,
    List<ZipEntryInfo> entries, {
    bool sniffDimensions = true,
  }) async {
    ZipEntryInfo? comicInfoEntry;
    final imageEntries = <ZipEntryInfo>[];

    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final normalized = entry.name.replaceAll(r'\', '/');
      final baseName = normalized.split('/').last.toLowerCase();
      if (baseName == 'comicinfo.xml' && !normalized.startsWith('__MACOSX/')) {
        comicInfoEntry ??= entry;
        continue;
      }
      if (isSupportedComicImagePath(normalized)) {
        if (entry.isEncrypted) {
          throw ArchiveException(ArchiveErrorKind.encryptedArchive, entry.name);
        }
        if (entry.compressionMethod != 0 && entry.compressionMethod != 8) {
          throw ArchiveException(
            ArchiveErrorKind.unsupportedCompression,
            'Method ${entry.compressionMethod} in ${entry.name}',
          );
        }
        imageEntries.add(entry);
      }
    }

    if (imageEntries.isEmpty) {
      throw const ArchiveException(ArchiveErrorKind.noImages);
    }

    imageEntries.sort(
      (ZipEntryInfo a, ZipEntryInfo b) => naturalCompare(a.name, b.name),
    );

    Uint8List? comicInfoBytes;
    if (comicInfoEntry != null && !comicInfoEntry.isEncrypted) {
      try {
        comicInfoBytes = await _extractEntry(source, comicInfoEntry);
      } on ArchiveException {
        // 损坏的元数据文件不应阻断漫画正文阅读。
        comicInfoBytes = null;
      }
    }

    final pages = <ArchivePageEntry>[];
    for (var i = 0; i < imageEntries.length; i++) {
      final item = imageEntries[i];
      ImageSize? dims;
      if (sniffDimensions) {
        dims = await _sniffEntryDimensions(source, item);
      }
      pages.add(
        ArchivePageEntry(
          number: i + 1,
          entryName: item.name,
          uncompressedSize: item.uncompressedSize,
          compressedSize: item.compressedSize,
          localHeaderOffset: item.localHeaderOffset,
          compressionMethod: item.compressionMethod,
          width: dims?.width,
          height: dims?.height,
          mediaType: mediaTypeForPath(item.name),
        ),
      );
    }

    return ZipComicReader._(
      source: source,
      pages: pages,
      comicInfoBytes: comicInfoBytes,
      chapters: resolveArchiveChapters(
        pages: pages,
        comicInfoBytes: comicInfoBytes,
      ),
    );
  }

  /// 利用数据库已缓存的页索引表直接构造读取器（阅读器打开时零 EOCD 扫描延迟）。
  factory ZipComicReader.fromIndexedPages(
    RandomAccessByteSource source,
    List<ArchivePageEntry> indexedPages,
  ) {
    return ZipComicReader._(source: source, pages: indexedPages);
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
  Future<Uint8List> readPage(int pageNumber) {
    if (pageNumber < 1 || pageNumber > pages.length) {
      return Future<Uint8List>.error(
        ArchiveException(
          ArchiveErrorKind.pageOutOfRange,
          'Page $pageNumber out of 1..${pages.length}',
        ),
      );
    }
    final entry = pages[pageNumber - 1];
    return _extractEntry(
      _source,
      ZipEntryInfo(
        name: entry.entryName,
        compressedSize: entry.compressedSize,
        uncompressedSize: entry.uncompressedSize,
        localHeaderOffset: entry.localHeaderOffset,
        compressionMethod: entry.compressionMethod,
        generalPurposeBitFlag: 0,
      ),
    );
  }

  @override
  Future<void> close() => _source.close();

  static Future<ImageSize?> sniffEntryDimensions(
    RandomAccessByteSource source,
    ZipEntryInfo entry,
  ) => _sniffEntryDimensions(source, entry);

  static Future<Uint8List> extractEntry(
    RandomAccessByteSource source,
    ZipEntryInfo entry,
  ) => _extractEntry(source, entry);

  static Future<ImageSize?> _sniffEntryDimensions(
    RandomAccessByteSource source,
    ZipEntryInfo entry,
  ) async {
    try {
      if (entry.compressionMethod == 0) {
        final dataOffset = await _resolveDataOffset(
          source,
          entry.localHeaderOffset,
        );
        final toRead = entry.uncompressedSize < _maxHeaderSniffBytes
            ? entry.uncompressedSize
            : _maxHeaderSniffBytes;
        final headerSlice = await source.readRange(dataOffset, toRead);
        return sniffImageDimensions(headerSlice);
      }
      final decoded = await _extractEntry(source, entry);
      return sniffImageDimensions(decoded);
    } on Object {
      return null;
    }
  }

  static Future<int> _resolveDataOffset(
    RandomAccessByteSource source,
    int localHeaderOffset,
  ) async {
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
    if ((gpFlag & 0x0001) != 0) {
      throw const ArchiveException(ArchiveErrorKind.encryptedArchive);
    }
    final nameLen = view.getUint16(26, Endian.little);
    final extraLen = view.getUint16(28, Endian.little);
    return localHeaderOffset + 30 + nameLen + extraLen;
  }

  static Future<Uint8List> _extractEntry(
    RandomAccessByteSource source,
    ZipEntryInfo entry,
  ) async {
    final dataOffset = await _resolveDataOffset(
      source,
      entry.localHeaderOffset,
    );
    final raw = await source.readRange(dataOffset, entry.compressedSize);
    if (raw.length < entry.compressedSize) {
      throw ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Truncated entry payload for ${entry.name}',
      );
    }
    switch (entry.compressionMethod) {
      case 0:
        return Uint8List.fromList(raw);
      case 8:
        try {
          final inflated = ZLibCodec(raw: true).decode(raw);
          return inflated is Uint8List
              ? inflated
              : Uint8List.fromList(inflated);
        } on FormatException catch (e) {
          throw ArchiveException(ArchiveErrorKind.corruptedArchive, e.message);
        } on IOException catch (e) {
          throw ArchiveException(
            ArchiveErrorKind.corruptedArchive,
            e.toString(),
          );
        }
      default:
        throw ArchiveException(
          ArchiveErrorKind.unsupportedCompression,
          'Unsupported compression method ${entry.compressionMethod}',
        );
    }
  }
}
