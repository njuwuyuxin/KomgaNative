import 'dart:typed_data';

import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 基于平台原生 PDF 引擎（Android `PdfRenderer` / iOS `PDFKit`）的漫画读取器适配器（LMB-11）。
///
/// 实现统一 [ComicArchiveReader] 接口，零拷贝按需光栅化指定页，并支持：
/// - 缩略图快速渲染（480px 宽）；
/// - 标准阅读渲染（1600px 宽）；
/// - 缩放后高清重绘（最高 3200px 宽）；
/// - PDF 内嵌大纲直接映射为单本书内部章节目录。
final class NativePdfComicReader implements ComicArchiveReader {
  NativePdfComicReader._({
    required NativePdfBridge bridge,
    required String filePath,
    required List<ArchivePageEntry> pages,
    required ComicInfoMetadata? metadata,
    required List<ArchiveChapter> chapters,
    String? password,
  }) : _bridge = bridge,
       _filePath = filePath,
       _password = password,
       pages = List<ArchivePageEntry>.unmodifiable(pages),
       embeddedMetadata = metadata,
       chapters = List<ArchiveChapter>.unmodifiable(chapters);

  static const int defaultThumbnailWidthPx = 480;
  static const int defaultDisplayWidthPx = 1600;
  static const int defaultZoomHdWidthPx = 2800;

  static Future<NativePdfComicReader> open(
    NativePdfBridge bridge,
    String filePath, {
    String? password,
  }) async {
    final PdfDocumentInfo info;
    try {
      info = await bridge.inspect(filePath, password: password);
    } on PdfPlatformException catch (e) {
      throw _mapPdfError(e);
    }

    if (info.pageCount <= 0) {
      throw const ArchiveException(ArchiveErrorKind.noImages, 'Empty PDF');
    }

    final pages = <ArchivePageEntry>[];
    for (var i = 0; i < info.pageCount; i++) {
      final metrics = i < info.pages.length ? info.pages[i] : null;
      final wPt = metrics?.widthPt ?? 800;
      final hPt = metrics?.heightPt ?? 1200;
      pages.add(
        ArchivePageEntry(
          number: i + 1,
          entryName: 'page_${(i + 1).toString().padLeft(4, '0')}.png',
          uncompressedSize: 0,
          width: wPt * 2,
          height: hPt * 2,
          mediaType: 'image/png',
        ),
      );
    }

    final chapters = <ArchiveChapter>[];
    final seenPages = <int>{};
    for (final item in info.outline) {
      final clamped = item.startPage.clamp(1, info.pageCount);
      if (seenPages.add(clamped)) {
        chapters.add(ArchiveChapter(title: item.title, startPage: clamped));
      }
    }
    chapters.sort((a, b) => a.startPage.compareTo(b.startPage));

    final metadata = (info.title != null || info.author != null)
        ? ComicInfoMetadata(
            title: info.title,
            authors: info.author != null
                ? <String>[info.author!]
                : const <String>[],
          )
        : null;

    return NativePdfComicReader._(
      bridge: bridge,
      filePath: filePath,
      pages: pages,
      metadata: metadata,
      chapters: chapters,
      password: password,
    );
  }

  /// 利用数据库已缓存的页尺寸直接构造，打开阅读器时零 inspect 延迟。
  factory NativePdfComicReader.fromIndexedPages(
    NativePdfBridge bridge,
    String filePath,
    List<ArchivePageEntry> indexedPages, {
    String? password,
  }) {
    return NativePdfComicReader._(
      bridge: bridge,
      filePath: filePath,
      pages: indexedPages,
      metadata: null,
      chapters: const <ArchiveChapter>[],
      password: password,
    );
  }

  final NativePdfBridge _bridge;
  final String _filePath;
  final String? _password;

  @override
  final List<ArchivePageEntry> pages;

  @override
  Uint8List? get comicInfoBytes => null;

  @override
  final ComicInfoMetadata? embeddedMetadata;

  @override
  final List<ArchiveChapter> chapters;

  @override
  Future<Uint8List> readPage(int pageNumber) =>
      renderAtWidth(pageNumber, targetWidthPx: defaultDisplayWidthPx);

  /// 按指定宽度像素光栅化单页（供缩略图 480px 或缩放高清重绘 2800px 使用）。
  Future<Uint8List> renderAtWidth(
    int pageNumber, {
    required int targetWidthPx,
  }) async {
    if (pageNumber < 1 || pageNumber > pages.length) {
      throw ArchiveException(
        ArchiveErrorKind.pageOutOfRange,
        'PDF page $pageNumber out of 1..${pages.length}',
      );
    }
    try {
      return await _bridge.renderPage(
        filePath: _filePath,
        pageNumber: pageNumber,
        targetWidthPx: targetWidthPx,
        password: _password,
      );
    } on PdfPlatformException catch (e) {
      throw _mapPdfError(e);
    }
  }

  @override
  Future<Uint8List?> readCoverImage() async => null;

  @override
  Future<void> close() => _bridge.closeDocument(_filePath);

  static ArchiveException _mapPdfError(PdfPlatformException e) {
    final kind = switch (e.kind) {
      PdfOpenErrorKind.invalidPassword => ArchiveErrorKind.encryptedArchive,
      PdfOpenErrorKind.corrupted => ArchiveErrorKind.corruptedArchive,
      PdfOpenErrorKind.unsupported => ArchiveErrorKind.unsupportedContainer,
      PdfOpenErrorKind.ioError => ArchiveErrorKind.ioError,
    };
    return ArchiveException(kind, e.message);
  }
}
