import 'dart:convert';
import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/byte_source.dart';
import 'package:yomu_local_archive/src/chapter_extractor.dart';
import 'package:yomu_local_archive/src/comic_info_parser.dart';
import 'package:yomu_local_archive/src/epub_opf_parser.dart';
import 'package:yomu_local_archive/src/epub_toc_parser.dart';
import 'package:yomu_local_archive/src/image_dimensions.dart';
import 'package:yomu_local_archive/src/natural_sort.dart';
import 'package:yomu_local_archive/src/tar_page_reader.dart';
import 'package:yomu_local_archive/src/zip_directory.dart';
import 'package:yomu_local_archive/src/zip_page_reader.dart';

/// 判断 ZIP 中央目录条目是否符合 EPUB 容器结构。
bool isEpubZipEntries(List<ZipEntryInfo> entries) {
  for (final entry in entries) {
    final norm = normalizeArchivePath(entry.name).toLowerCase();
    if (norm == 'meta-inf/container.xml' || norm == 'mimetype') {
      return true;
    }
  }
  return false;
}

/// 统一归档探测打开入口：自动识别标准 CBZ/ZIP、固定版式漫画 EPUB 与 CBT/TAR。
Future<ComicArchiveReader> openComicArchive(
  RandomAccessByteSource source, {
  bool sniffDimensions = true,
  String? password,
}) async {
  try {
    final totalLength = await source.length();
    if (totalLength <= 0) {
      throw const ArchiveException(ArchiveErrorKind.emptyFile);
    }
    final peekLen = totalLength < 265 ? totalLength : 265;
    final head = await source.readRange(0, peekLen);
    if (sniffContainerMagic(head) == ContainerMagic.tar) {
      return await TarComicReader.open(
        source,
        sniffDimensions: sniffDimensions,
      );
    }

    final entries = await readZipCentralDirectory(source);
    if (isEpubZipEntries(entries)) {
      return await EpubComicReader.openWithEntries(
        source,
        entries,
        sniffDimensions: sniffDimensions,
      );
    }
    return await ZipComicReader.openWithEntries(
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

/// 漫画型 `EPUB`（固定版式 / 纯图单行本）按需随机读取器（LMB-04）。
///
/// 按 `META-INF/container.xml → content.opf → <spine>` 提取有序页图、阅读方向（RTL/LTR）
/// 与内嵌章节目录（`nav.xhtml` / `toc.ncx`），检测到纯文字小说 EPUB 时明确抛出
/// [ArchiveErrorKind.textOnlyEpub]。
final class EpubComicReader implements ComicArchiveReader {
  EpubComicReader._({
    required RandomAccessByteSource source,
    required List<ArchivePageEntry> pages,
    required ComicInfoMetadata metadata,
    required List<ArchiveChapter> chapters,
    ZipEntryInfo? standaloneCoverEntry,
  }) : _source = source,
       _standaloneCoverEntry = standaloneCoverEntry,
       pages = List<ArchivePageEntry>.unmodifiable(pages),
       embeddedMetadata = metadata,
       chapters = List<ArchiveChapter>.unmodifiable(chapters);

  static Future<EpubComicReader> open(
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

  static Future<EpubComicReader> openWithEntries(
    RandomAccessByteSource source,
    List<ZipEntryInfo> entries, {
    bool sniffDimensions = true,
  }) async {
    final byPath = <String, ZipEntryInfo>{};
    final byLower = <String, ZipEntryInfo>{};
    ZipEntryInfo? fallbackOpf;

    for (final entry in entries) {
      if (entry.isDirectory) continue;
      final norm = normalizeArchivePath(entry.name);
      final lower = norm.toLowerCase();
      byPath[norm] = entry;
      byLower[lower] = entry;
      if (lower.endsWith('.opf')) fallbackOpf ??= entry;
    }

    String? opfPath;
    final containerEntry = byLower['meta-inf/container.xml'];
    if (containerEntry != null && !containerEntry.isEncrypted) {
      final containerBytes = await ZipComicReader.extractEntry(
        source,
        containerEntry,
      );
      opfPath = parseContainerOpfPath(
        utf8.decode(containerBytes, allowMalformed: true),
      );
    }
    final opfEntry =
        (opfPath != null
            ? (byPath[opfPath] ?? byLower[opfPath.toLowerCase()])
            : null) ??
        fallbackOpf;
    if (opfEntry == null) {
      throw const ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Missing EPUB OPF package document',
      );
    }
    if (opfEntry.isEncrypted) {
      throw ArchiveException(ArchiveErrorKind.encryptedArchive, opfEntry.name);
    }

    final opfBytes = await ZipComicReader.extractEntry(source, opfEntry);
    final opfNormPath = normalizeArchivePath(opfEntry.name);
    final opf = parseEpubOpf(
      utf8.decode(opfBytes, allowMalformed: true),
      opfPath: opfNormPath,
    );

    final orderedImages = <ZipEntryInfo>[];
    final spineHrefToStartPage = <String, int>{};
    var totalTextChars = 0;

    for (final idref in opf.spineIds) {
      final item = opf.manifest[idref];
      if (item == null) continue;
      final target = byPath[item.href] ?? byLower[item.href.toLowerCase()];
      if (target == null) continue;
      if (target.isEncrypted) {
        throw ArchiveException(ArchiveErrorKind.encryptedArchive, target.name);
      }

      if (isSupportedComicImagePath(item.href)) {
        final pageNum = orderedImages.length + 1;
        spineHrefToStartPage.putIfAbsent(
          item.href.toLowerCase(),
          () => pageNum,
        );
        orderedImages.add(target);
        continue;
      }

      final isMarkup =
          item.mediaType.contains('html') ||
          item.mediaType.contains('xml') ||
          item.href.toLowerCase().endsWith('.xhtml') ||
          item.href.toLowerCase().endsWith('.html') ||
          item.href.toLowerCase().endsWith('.htm') ||
          item.href.toLowerCase().endsWith('.svg');
      if (!isMarkup) continue;

      final docBytes = await ZipComicReader.extractEntry(source, target);
      final extracted = extractEpubDocumentImages(
        utf8.decode(docBytes, allowMalformed: true),
        documentPath: item.href,
      );
      totalTextChars += extracted.textChars;

      for (final imgPath in extracted.imagePaths) {
        if (!isSupportedComicImagePath(imgPath)) continue;
        final imgEntry = byPath[imgPath] ?? byLower[imgPath.toLowerCase()];
        if (imgEntry == null) continue;
        if (imgEntry.isEncrypted) {
          throw ArchiveException(
            ArchiveErrorKind.encryptedArchive,
            imgEntry.name,
          );
        }
        final pageNum = orderedImages.length + 1;
        spineHrefToStartPage.putIfAbsent(
          item.href.toLowerCase(),
          () => pageNum,
        );
        orderedImages.add(imgEntry);
      }
    }

    // 纯文字小说拦截边界：有效漫画图片 < 3 张且存在显著正文文字 → 明确报 textOnlyEpub。
    if ((orderedImages.length < 3 && totalTextChars >= 500) ||
        (orderedImages.isEmpty && totalTextChars > 0)) {
      throw const ArchiveException(
        ArchiveErrorKind.textOnlyEpub,
        'Reflowable text-only EPUB is not supported; Yomu focuses on comics',
      );
    }
    if (orderedImages.isEmpty) {
      throw const ArchiveException(ArchiveErrorKind.noImages);
    }

    var frontCoverIndex = opf.metadata.frontCoverPageIndex;
    ZipEntryInfo? standaloneCover;
    final coverHref = opf.coverImageHref;
    final coverHrefLower = coverHref?.toLowerCase();
    if (frontCoverIndex == null &&
        coverHref != null &&
        coverHrefLower != null) {
      for (var i = 0; i < orderedImages.length; i++) {
        if (normalizeArchivePath(orderedImages[i].name).toLowerCase() ==
            coverHrefLower) {
          frontCoverIndex = i;
          break;
        }
      }
      if (frontCoverIndex == null) {
        final entry = byPath[coverHref] ?? byLower[coverHrefLower];
        if (entry != null &&
            !entry.isEncrypted &&
            isSupportedComicImagePath(entry.name)) {
          standaloneCover = entry;
        }
      }
    }

    final chapters = await resolveEpubChapters(
      source: source,
      opf: opf,
      byPath: byPath,
      byLower: byLower,
      spineHrefToStartPage: spineHrefToStartPage,
    );

    final pages = <ArchivePageEntry>[];
    for (var i = 0; i < orderedImages.length; i++) {
      final img = orderedImages[i];
      ImageSize? dims;
      if (sniffDimensions) {
        dims = await ZipComicReader.sniffEntryDimensions(source, img);
      }
      pages.add(
        ArchivePageEntry(
          number: i + 1,
          entryName: img.name,
          uncompressedSize: img.uncompressedSize,
          compressedSize: img.compressedSize,
          localHeaderOffset: img.localHeaderOffset,
          compressionMethod: img.compressionMethod,
          width: dims?.width,
          height: dims?.height,
          mediaType: mediaTypeForPath(img.name),
        ),
      );
    }

    final metadata = ComicInfoMetadata(
      series: opf.metadata.series,
      title: opf.metadata.title,
      number: opf.metadata.number,
      summary: opf.metadata.summary,
      authors: opf.metadata.authors,
      publisher: opf.metadata.publisher,
      tags: opf.metadata.tags,
      readingDirection: opf.direction,
      frontCoverPageIndex: frontCoverIndex,
    );

    return EpubComicReader._(
      source: source,
      pages: pages,
      metadata: metadata,
      chapters: chapters,
      standaloneCoverEntry: standaloneCover,
    );
  }

  final RandomAccessByteSource _source;
  final ZipEntryInfo? _standaloneCoverEntry;

  @override
  final List<ArchivePageEntry> pages;

  @override
  Uint8List? get comicInfoBytes => null;

  @override
  final ComicInfoMetadata embeddedMetadata;

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
    return ZipComicReader.extractEntry(
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
  Future<Uint8List?> readCoverImage() async {
    final entry = _standaloneCoverEntry;
    if (entry == null) return null;
    return ZipComicReader.extractEntry(_source, entry);
  }

  @override
  Future<void> close() => _source.close();
}
