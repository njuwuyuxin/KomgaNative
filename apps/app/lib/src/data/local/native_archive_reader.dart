import 'dart:typed_data';

import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 平台原生 `CBR (RAR4/RAR5)` 与 `CB7 (7z)` 漫画读取器（LMB-12，ADR 0010）。
///
/// 对固实压缩包自动启用 [SolidArchiveWindowCache]（每次单趟批量抽出 6 页滑动窗口），
/// 避免逐页从头解压导致 \(O(N^2)\) 卡顿。
final class NativeArchiveComicReader implements ComicArchiveReader {
  NativeArchiveComicReader._({
    required NativeArchiveBridge bridge,
    required String filePath,
    required NativeArchiveFormat format,
    required bool isSolid,
    required List<ArchivePageEntry> pages,
    required Uint8List? comicInfoBytes,
    required List<ArchiveChapter> chapters,
    String? password,
  }) : _bridge = bridge,
       _filePath = filePath,
       format = format,
       isSolid = isSolid,
       _password = password,
       pages = List<ArchivePageEntry>.unmodifiable(pages),
       comicInfoBytes = comicInfoBytes,
       chapters = List<ArchiveChapter>.unmodifiable(chapters),
       _solidCache = isSolid
           ? SolidArchiveWindowCache(
               orderedEntryNames: pages
                   .map((p) => p.entryName)
                   .toList(growable: false),
               extractWindow: (List<String> names) => bridge.extractWindow(
                 filePath: filePath,
                 entryNames: names,
                 password: password,
               ),
             )
           : null;

  static Future<NativeArchiveComicReader> open(
    NativeArchiveBridge bridge,
    String filePath, {
    String? password,
    bool sniffFirstCoverDimensions = true,
  }) async {
    final NativeArchiveListing listing;
    try {
      listing = await bridge.listEntries(filePath, password: password);
    } on NativeArchiveException catch (e) {
      throw _mapArchiveError(e);
    }

    String? comicInfoEntryName;
    final imageEntries = <NativeArchiveEntry>[];
    for (final entry in listing.entries) {
      if (entry.isDirectory) continue;
      final norm = entry.entryName.replaceAll(r'\', '/');
      final lowerBase = norm.split('/').last.toLowerCase();
      if (lowerBase == 'comicinfo.xml' &&
          !norm.startsWith('__MACOSX/') &&
          comicInfoEntryName == null) {
        comicInfoEntryName = entry.entryName;
      } else if (isSupportedComicImagePath(norm)) {
        imageEntries.add(entry);
      }
    }

    if (imageEntries.isEmpty) {
      throw const ArchiveException(ArchiveErrorKind.noImages);
    }
    imageEntries.sort((a, b) => naturalCompare(a.entryName, b.entryName));

    Uint8List? comicInfoBytes;
    if (comicInfoEntryName != null) {
      try {
        comicInfoBytes = await bridge.extractEntry(
          filePath: filePath,
          entryName: comicInfoEntryName,
          password: password,
        );
      } on NativeArchiveException catch (e) {
        if (e.kind == NativeArchiveErrorKind.invalidPassword) {
          throw _mapArchiveError(e);
        }
        comicInfoBytes = null;
      }
    }

    ImageSize? firstDims;
    if (sniffFirstCoverDimensions) {
      try {
        final firstBytes = await bridge.extractEntry(
          filePath: filePath,
          entryName: imageEntries.first.entryName,
          password: password,
        );
        firstDims = sniffImageDimensions(firstBytes);
      } on NativeArchiveException catch (e) {
        if (e.kind == NativeArchiveErrorKind.invalidPassword) {
          throw _mapArchiveError(e);
        }
      }
    }

    final pages = <ArchivePageEntry>[
      for (var i = 0; i < imageEntries.length; i++)
        ArchivePageEntry(
          number: i + 1,
          entryName: imageEntries[i].entryName,
          uncompressedSize: imageEntries[i].uncompressedSize,
          width: i == 0 ? firstDims?.width : null,
          height: i == 0 ? firstDims?.height : null,
          mediaType: mediaTypeForPath(imageEntries[i].entryName),
        ),
    ];

    return NativeArchiveComicReader._(
      bridge: bridge,
      filePath: filePath,
      format: listing.format,
      isSolid: listing.isSolid,
      pages: pages,
      comicInfoBytes: comicInfoBytes,
      chapters: resolveArchiveChapters(
        pages: pages,
        comicInfoBytes: comicInfoBytes,
      ),
      password: password,
    );
  }

  /// 利用数据库已缓存的页表直接构造读取器（固实 CB7 默认开启滑动窗口）。
  factory NativeArchiveComicReader.fromIndexedPages(
    NativeArchiveBridge bridge,
    String filePath,
    List<ArchivePageEntry> indexedPages, {
    required NativeArchiveFormat format,
    required bool isSolid,
    String? password,
  }) {
    return NativeArchiveComicReader._(
      bridge: bridge,
      filePath: filePath,
      format: format,
      isSolid: isSolid,
      pages: indexedPages,
      comicInfoBytes: null,
      chapters: const <ArchiveChapter>[],
      password: password,
    );
  }

  final NativeArchiveBridge _bridge;
  final String _filePath;
  final NativeArchiveFormat format;
  final bool isSolid;
  final String? _password;
  final SolidArchiveWindowCache? _solidCache;

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
    try {
      final cache = _solidCache;
      if (cache != null) {
        final bytes = await cache.readPage(pageNumber);
        if (bytes != null) return bytes;
      }
      return await _bridge.extractEntry(
        filePath: _filePath,
        entryName: pages[pageNumber - 1].entryName,
        password: _password,
      );
    } on NativeArchiveException catch (e) {
      throw _mapArchiveError(e);
    }
  }

  @override
  Future<Uint8List?> readCoverImage() async => null;

  @override
  Future<void> close() async {
    _solidCache?.clear();
    await _bridge.closeArchive(_filePath);
  }

  static ArchiveException _mapArchiveError(NativeArchiveException e) {
    final kind = switch (e.kind) {
      NativeArchiveErrorKind.invalidPassword =>
        ArchiveErrorKind.encryptedArchive,
      NativeArchiveErrorKind.corrupted => ArchiveErrorKind.corruptedArchive,
      NativeArchiveErrorKind.unsupported =>
        ArchiveErrorKind.unsupportedContainer,
      NativeArchiveErrorKind.ioError => ArchiveErrorKind.ioError,
    };
    return ArchiveException(kind, e.message);
  }
}
