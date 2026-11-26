import 'dart:typed_data';

import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/archive_isolate.dart';
import 'package:yomu_local_archive/src/byte_source.dart';
import 'package:yomu_local_archive/src/chapter_extractor.dart';
import 'package:yomu_local_archive/src/comic_info_parser.dart';
import 'package:yomu_local_archive/src/image_dimensions.dart';
import 'package:yomu_local_archive/src/natural_sort.dart';
import 'package:yomu_local_archive/src/zip_crypto.dart';
import 'package:yomu_local_archive/src/zip_directory.dart';
import 'package:yomu_local_archive/src/zip_entry_extractor.dart';

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

/// 统一的本地漫画容器读取接口（屏蔽 ZIP/CBZ、漫画 EPUB、TAR、PDF、CBR/CB7 与图片文件夹差异）。
abstract interface class ComicArchiveReader {
  List<ArchivePageEntry> get pages;

  /// 若归档根目录或子目录存在 `ComicInfo.xml`，返回其原始字节；否则为 `null`。
  Uint8List? get comicInfoBytes;

  /// 容器自携带的结构化元数据（如 EPUB `content.opf` 或 PDF 元信息）；未提供时返回 `null`。
  ComicInfoMetadata? get embeddedMetadata;

  /// 单本书内部章节目录（如 EPUB TOC、PDF 大纲、子文件夹起始页、`ComicInfo.xml` 书签）。
  List<ArchiveChapter> get chapters;

  /// 按 1 基页码按需读取并解压单页图片字节。
  Future<Uint8List> readPage(int pageNumber);

  /// 读取容器独立声明的封面字节（如 EPUB 未列入 `<spine>` 的 `cover-image`）；无则 `null`。
  Future<Uint8List?> readCoverImage();

  Future<void> close();
}

/// 基于中央目录偏移的 \(O(1)\) 随机访问 ZIP / CBZ 漫画读取器（支持 ZipCrypto 密码解锁）。
final class ZipComicReader implements ComicArchiveReader {
  ZipComicReader._({
    required RandomAccessByteSource source,
    required List<ArchivePageEntry> pages,
    Uint8List? comicInfoBytes,
    List<ArchiveChapter> chapters = const <ArchiveChapter>[],
    Uint8List? passwordBytes,
    List<ZipEntryInfo>? rawEntries,
  }) : _source = source,
       _passwordBytes = passwordBytes,
       _rawEntries = rawEntries,
       pages = List<ArchivePageEntry>.unmodifiable(pages),
       comicInfoBytes = comicInfoBytes,
       chapters = List<ArchiveChapter>.unmodifiable(chapters);

  /// 扫描中央目录建立页表、提取 `ComicInfo.xml`，并可选嗅探每页宽高（支持密码解锁）。
  static Future<ZipComicReader> open(
    RandomAccessByteSource source, {
    bool sniffDimensions = true,
    String? password,
  }) async {
    try {
      final entries = await readZipCentralDirectory(source);
      return await openWithEntries(
        source,
        entries,
        sniffDimensions: sniffDimensions,
        password: password,
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
    String? password,
  }) async {
    ZipEntryInfo? comicInfoEntry;
    final imageEntries = <ZipEntryInfo>[];
    var hasEncrypted = false;

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
          if (password == null || password.isEmpty) {
            throw ArchiveException(
              ArchiveErrorKind.encryptedArchive,
              entry.name,
            );
          }
          hasEncrypted = true;
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

    Uint8List? resolvedPwd;
    if (hasEncrypted) {
      final firstEnc = imageEntries.firstWhere((e) => e.isEncrypted);
      final dataOffset = await resolveZipEntryDataOffset(
        source,
        firstEnc.localHeaderOffset,
        allowEncrypted: true,
      );
      final rawEnc = await source.readRange(
        dataOffset,
        firstEnc.compressedSize,
      );
      final targetPassword = password!;
      final probed =
          await offloadBytesParse<
            ({Uint8List passwordBytes, Uint8List plainBytes})?
          >(
            rawEnc,
            (Uint8List bytes) =>
                probeZipCryptoPassword(bytes, firstEnc, targetPassword),
            thresholdBytes: kZipCryptoIsolateThreshold,
          );
      if (probed == null) {
        throw const ArchiveException(
          ArchiveErrorKind.encryptedArchive,
          'Invalid ZIP password',
        );
      }
      resolvedPwd = probed.passwordBytes;
    }

    Uint8List? comicInfoBytes;
    if (comicInfoEntry != null &&
        (!comicInfoEntry.isEncrypted || resolvedPwd != null)) {
      try {
        comicInfoBytes = await extractZipEntryBytes(
          source,
          comicInfoEntry,
          passwordBytes: resolvedPwd,
        );
      } on ArchiveException {
        comicInfoBytes = null;
      }
    }

    final pages = <ArchivePageEntry>[];
    for (var i = 0; i < imageEntries.length; i++) {
      final item = imageEntries[i];
      final dims = sniffDimensions
          ? await sniffZipEntryDimensions(
              source,
              item,
              passwordBytes: resolvedPwd,
            )
          : null;
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
      passwordBytes: resolvedPwd,
      rawEntries: hasEncrypted ? imageEntries : null,
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
  final Uint8List? _passwordBytes;
  final List<ZipEntryInfo>? _rawEntries;

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
    final raw = _rawEntries;
    if (raw != null && pageNumber - 1 < raw.length) {
      return extractZipEntryBytes(
        _source,
        raw[pageNumber - 1],
        passwordBytes: _passwordBytes,
      );
    }
    final entry = pages[pageNumber - 1];
    return extractZipEntryBytes(
      _source,
      ZipEntryInfo(
        name: entry.entryName,
        compressedSize: entry.compressedSize,
        uncompressedSize: entry.uncompressedSize,
        localHeaderOffset: entry.localHeaderOffset,
        compressionMethod: entry.compressionMethod,
        generalPurposeBitFlag: 0,
      ),
      passwordBytes: _passwordBytes,
    );
  }

  @override
  Future<Uint8List?> readCoverImage() async => null;

  @override
  Future<void> close() => _source.close();

  static Future<ImageSize?> sniffEntryDimensions(
    RandomAccessByteSource source,
    ZipEntryInfo entry,
  ) => sniffZipEntryDimensions(source, entry);

  static Future<Uint8List> extractEntry(
    RandomAccessByteSource source,
    ZipEntryInfo entry,
  ) => extractZipEntryBytes(source, entry);
}
