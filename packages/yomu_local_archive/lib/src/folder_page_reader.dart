import 'dart:io';
import 'dart:typed_data';

import 'package:yomu_local_archive/src/archive_errors.dart';
import 'package:yomu_local_archive/src/chapter_extractor.dart';
import 'package:yomu_local_archive/src/comic_info_parser.dart';
import 'package:yomu_local_archive/src/image_dimensions.dart';
import 'package:yomu_local_archive/src/natural_sort.dart';
import 'package:yomu_local_archive/src/zip_page_reader.dart';

const int _folderHeaderSniffBytes = 32768;

/// 本地图片文件夹漫画读取器（与 [ZipComicReader] 实现同一套 [ComicArchiveReader]）。
final class FolderComicReader implements ComicArchiveReader {
  FolderComicReader._({
    required Directory root,
    required List<ArchivePageEntry> pages,
    Uint8List? comicInfoBytes,
    List<ArchiveChapter> chapters = const <ArchiveChapter>[],
  }) : _root = root,
       pages = List<ArchivePageEntry>.unmodifiable(pages),
       comicInfoBytes = comicInfoBytes,
       chapters = List<ArchiveChapter>.unmodifiable(chapters);

  /// 扫描 [directory] 下的图片序列与可选 `ComicInfo.xml`。
  static Future<FolderComicReader> open(
    Directory directory, {
    bool sniffDimensions = true,
  }) async {
    if (!await directory.exists()) {
      throw ArchiveException(
        ArchiveErrorKind.ioError,
        'Directory does not exist: ${directory.path}',
      );
    }

    final rootPath = _normalizeDirPath(directory.path);
    File? comicInfoFile;
    final imageFiles = <({String relPath, File file})>[];

    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final fullPath = entity.path.replaceAll(r'\', '/');
        final relPath = fullPath.startsWith(rootPath)
            ? fullPath.substring(rootPath.length)
            : fullPath.split('/').last;
        final baseName = relPath.split('/').last.toLowerCase();
        if (baseName == 'comicinfo.xml' &&
            !relPath.startsWith('__MACOSX/') &&
            comicInfoFile == null) {
          comicInfoFile = entity;
          continue;
        }
        if (isSupportedComicImagePath(relPath)) {
          imageFiles.add((relPath: relPath, file: entity));
        }
      }
    } on FileSystemException catch (e) {
      throw ArchiveException(ArchiveErrorKind.ioError, e.message);
    }

    if (imageFiles.isEmpty) {
      throw const ArchiveException(ArchiveErrorKind.noImages);
    }

    imageFiles.sort((a, b) => naturalCompare(a.relPath, b.relPath));

    Uint8List? comicInfoBytes;
    if (comicInfoFile != null) {
      try {
        comicInfoBytes = await comicInfoFile.readAsBytes();
      } on FileSystemException {
        comicInfoBytes = null;
      }
    }

    final pages = <ArchivePageEntry>[];
    for (var i = 0; i < imageFiles.length; i++) {
      final item = imageFiles[i];
      int sizeBytes = 0;
      ImageSize? dims;
      try {
        sizeBytes = await item.file.length();
        if (sniffDimensions && sizeBytes > 0) {
          final raf = await item.file.open();
          try {
            final toRead = sizeBytes < _folderHeaderSniffBytes
                ? sizeBytes
                : _folderHeaderSniffBytes;
            final header = await raf.read(toRead);
            dims = sniffImageDimensions(header);
          } finally {
            await raf.close();
          }
        }
      } on FileSystemException {
        // 单个文件探测失败时退回未知尺寸，交给实际阅读阶段处理。
      }
      pages.add(
        ArchivePageEntry(
          number: i + 1,
          entryName: item.relPath,
          uncompressedSize: sizeBytes,
          width: dims?.width,
          height: dims?.height,
          mediaType: mediaTypeForPath(item.relPath),
        ),
      );
    }

    return FolderComicReader._(
      root: directory,
      pages: pages,
      comicInfoBytes: comicInfoBytes,
      chapters: resolveArchiveChapters(
        pages: pages,
        comicInfoBytes: comicInfoBytes,
      ),
    );
  }

  /// 利用数据库已缓存的页表直接构造文件夹读取器。
  factory FolderComicReader.fromIndexedPages(
    Directory directory,
    List<ArchivePageEntry> indexedPages,
  ) {
    return FolderComicReader._(root: directory, pages: indexedPages);
  }

  final Directory _root;

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
    final rel = pages[pageNumber - 1].entryName;
    if (rel.split('/').contains('..')) {
      throw ArchiveException(
        ArchiveErrorKind.corruptedArchive,
        'Unsafe relative path: $rel',
      );
    }
    final file = File('${_normalizeDirPath(_root.path)}$rel');
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw ArchiveException(ArchiveErrorKind.ioError, e.message);
    }
  }

  @override
  Future<Uint8List?> readCoverImage() async => null;

  @override
  Future<void> close() async {}

  static String _normalizeDirPath(String path) {
    final norm = path.replaceAll(r'\', '/');
    return norm.endsWith('/') ? norm : '$norm/';
  }
}
