import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/byte_cache.dart';
import 'package:yomu/src/data/local/external_byte_source.dart';
import 'package:yomu/src/data/local/external_roots_dao.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/local/native_pdf_reader.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/reader_repository.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 本机漫画阅读器仓库：复用已打开的归档文件句柄与 64 页内存 [ByteLruCache]，单页随机提取。
final class LocalReaderRepository implements ReaderRepository {
  static const int defaultPageCacheCapacity = 64;
  static const int _maxOpenArchives = 4;

  LocalReaderRepository(
    this._db,
    this._storage, {
    int pageCacheCapacity = defaultPageCacheCapacity,
    ExternalRootsBridge? externalRoots,
    NativePdfBridge? pdfBridge,
  }) : _pages = ByteLruCache(capacity: pageCacheCapacity),
       _externalRoots = externalRoots ?? ChannelExternalRootsBridge(),
       _pdfBridge = pdfBridge ?? ChannelNativePdfBridge();

  final ProgressDatabase _db;
  final LocalComicsStorage _storage;
  final ExternalRootsBridge _externalRoots;
  final NativePdfBridge _pdfBridge;
  final ByteLruCache _pages;
  final Map<String, Future<Uint8List>> _inFlight =
      <String, Future<Uint8List>>{};
  final LinkedHashMap<String, Future<ComicArchiveReader>> _openReaders =
      LinkedHashMap<String, Future<ComicArchiveReader>>();

  Future<void> dispose() async {
    final futures = _openReaders.values.toList(growable: false);
    _openReaders.clear();
    for (final future in futures) {
      try {
        final reader = await future;
        await reader.close();
      } on Object {
        // 销毁阶段忽略底层关闭异常。
      }
    }
  }

  /// 删除或重导某本书前主动关闭其打开的文件句柄（Windows 下释放文件锁必需）。
  Future<void> closeBookHandle(String bookId) async {
    final removed = _openReaders.remove(bookId);
    if (removed == null) return;
    try {
      final reader = await removed;
      await reader.close();
    } on Object {
      // 忽略已失效句柄。
    }
  }

  @override
  Future<Book?> book(String bookId) => _db.localBookById(bookId);

  @override
  Future<List<PageInfo>> pages(String bookId) async {
    final bookRow = await _db.localBookRowById(bookId);
    if (bookRow == null) throw const NotFoundFailure();

    final indexed = await _db.localPagesForBook(bookId);
    if (indexed.isNotEmpty) {
      return <PageInfo>[
        for (final p in indexed)
          PageInfo(
            number: p.pageNumber,
            width: p.width,
            height: p.height,
            mediaType: p.mediaType,
            sizeBytes: p.uncompressedSize,
          ),
      ];
    }

    try {
      final reader = await _acquireReader(bookId, bookRow);
      return reader.pages.map((e) => e.toPageInfo()).toList(growable: false);
    } on ArchiveException catch (e) {
      throw shelfFailureFromArchive(e);
    }
  }

  @override
  Future<Uint8List> pageImage(String bookId, int page) {
    final key = '$bookId#$page';
    final cached = _pages.get(key);
    if (cached != null) return Future<Uint8List>.value(cached);
    return _inFlight[key] ??= _loadAndCachePage(key, bookId, page);
  }

  @override
  Uint8List? cachedPageImage(String bookId, int page) =>
      _pages.peek('$bookId#$page');

  @override
  Future<Uint8List> pageThumbnail(String bookId, int page) async {
    final thumbKey = '$bookId#$page#thumb';
    final cached = _pages.get(thumbKey) ?? _pages.peek('$bookId#$page');
    if (cached != null) return cached;
    final bookRow = await _db.localBookRowById(bookId);
    if (bookRow != null &&
        (bookRow.storageKind == 'pdf' || bookRow.storageKind == 'ext_pdf')) {
      final reader = await _acquireReader(bookId, bookRow);
      if (reader is NativePdfComicReader) {
        final bytes = await reader.renderAtWidth(
          page,
          targetWidthPx: NativePdfComicReader.defaultThumbnailWidthPx,
        );
        _pages.put(thumbKey, bytes);
        return bytes;
      }
    }
    return pageImage(bookId, page);
  }

  /// PDF 缩放高清重绘接口（LMB-11）：按目标像素宽度重新光栅化当前页。
  Future<Uint8List?> renderHighResPage(
    String bookId,
    int page, {
    int targetWidthPx = NativePdfComicReader.defaultZoomHdWidthPx,
  }) async {
    final bookRow = await _db.localBookRowById(bookId);
    if (bookRow == null) return null;
    final reader = await _acquireReader(bookId, bookRow);
    if (reader is! NativePdfComicReader) return null;
    return reader.renderAtWidth(page, targetWidthPx: targetWidthPx);
  }

  @override
  Uint8List? cachedPageThumbnail(String bookId, int page) =>
      _pages.peek('$bookId#$page');

  Future<Uint8List> _loadAndCachePage(
    String key,
    String bookId,
    int page,
  ) async {
    try {
      final bookRow = await _db.localBookRowById(bookId);
      if (bookRow == null) throw const NotFoundFailure();
      final reader = await _acquireReader(bookId, bookRow);
      final bytes = await reader.readPage(page);
      _pages.put(key, bytes);
      return bytes;
    } on ShelfFailure {
      rethrow;
    } on ArchiveException catch (e) {
      _openReaders.remove(bookId)?.ignore();
      throw shelfFailureFromArchive(e);
    } finally {
      _inFlight.remove(key)?.ignore();
    }
  }

  Future<ComicArchiveReader> _acquireReader(String bookId, LocalBooksRow row) {
    final existing = _openReaders.remove(bookId);
    if (existing != null) {
      _openReaders[bookId] = existing;
      return existing;
    }

    while (_openReaders.length >= _maxOpenArchives) {
      final oldestKey = _openReaders.keys.first;
      final evicted = _openReaders.remove(oldestKey);
      if (evicted != null) {
        unawaited(evicted.then((r) => r.close()).catchError((Object _) {}));
      }
    }

    final created = _openArchiveReader(bookId, row);
    _openReaders[bookId] = created;
    return created;
  }

  Future<ComicArchiveReader> _openArchiveReader(
    String bookId,
    LocalBooksRow row,
  ) async {
    final indexedRows = await _db.localPagesForBook(bookId);
    final entries = <ArchivePageEntry>[
      for (final p in indexedRows)
        ArchivePageEntry(
          number: p.pageNumber,
          entryName: p.entryName,
          uncompressedSize: p.uncompressedSize,
          compressedSize: p.compressedSize,
          localHeaderOffset: p.localHeaderOffset,
          compressionMethod: p.compressionMethod,
          width: p.width,
          height: p.height,
          mediaType: p.mediaType,
        ),
    ];

    if (row.mountRootId != null) {
      return _openExternalArchiveReader(row, entries);
    }

    if (row.storageKind == 'folder') {
      final dir = await _storage.resolveDirectory(row.relativePath);
      if (!await dir.exists()) {
        throw const ArchiveException(
          ArchiveErrorKind.ioError,
          'Missing folder',
        );
      }
      return entries.isNotEmpty
          ? FolderComicReader.fromIndexedPages(dir, entries)
          : FolderComicReader.open(dir);
    }

    final file = await _storage.resolveFile(row.relativePath);
    if (row.storageKind == 'pdf') {
      return entries.isNotEmpty
          ? NativePdfComicReader.fromIndexedPages(
              _pdfBridge,
              file.path,
              entries,
            )
          : NativePdfComicReader.open(_pdfBridge, file.path);
    }
    final source = await FileByteSource.open(file);
    if (row.storageKind == 'tar') {
      return entries.isNotEmpty
          ? TarComicReader.fromIndexedPages(source, entries)
          : TarComicReader.open(source);
    }
    return entries.isNotEmpty
        ? ZipComicReader.fromIndexedPages(source, entries)
        : openComicArchive(source);
  }

  Future<ComicArchiveReader> _openExternalArchiveReader(
    LocalBooksRow row,
    List<ArchivePageEntry> entries,
  ) async {
    final rootRow = await _db.mountedRootById(row.mountRootId!);
    final root = rootRow == null ? null : mountedRootFromRow(rootRow);

    if (row.isCloudPlaceholder) {
      await _externalRoots.triggerCloudDownload(row.relativePath, root: root);
      throw const ArchiveException(
        ArchiveErrorKind.ioError,
        'Cloud placeholder is downloading; please retry shortly',
      );
    }

    if (row.storageKind == 'ext_folder') {
      final dir = Directory(row.relativePath);
      return entries.isNotEmpty
          ? FolderComicReader.fromIndexedPages(dir, entries)
          : FolderComicReader.open(dir);
    }

    if (row.storageKind == 'ext_pdf') {
      return entries.isNotEmpty
          ? NativePdfComicReader.fromIndexedPages(
              _pdfBridge,
              row.relativePath,
              entries,
            )
          : NativePdfComicReader.open(_pdfBridge, row.relativePath);
    }

    final useBridge =
        row.storageKind.startsWith('saf_') ||
        root?.kind == ExternalRootKind.androidSaf ||
        root?.kind == ExternalRootKind.iosBookmark;
    final RandomAccessByteSource source = useBridge
        ? ExternalRangeByteSource(
            bridge: _externalRoots,
            uri: row.relativePath,
            root: root,
            knownLength: row.sizeBytes > 0 ? row.sizeBytes : null,
          )
        : await FileByteSource.open(File(row.relativePath));

    if (row.storageKind.endsWith('_tar')) {
      return entries.isNotEmpty
          ? TarComicReader.fromIndexedPages(source, entries)
          : TarComicReader.open(source);
    }
    return entries.isNotEmpty
        ? ZipComicReader.fromIndexedPages(source, entries)
        : openComicArchive(source);
  }
}
