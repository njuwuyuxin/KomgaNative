import 'dart:io';
import 'dart:typed_data';

import 'package:yomu/src/data/byte_cache.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/local/local_catalog_ondeck_dao.dart';
import 'package:yomu/src/data/local/local_catalog_query_dao.dart';
import 'package:yomu/src/data/local/local_comics_storage.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_local_archive/yomu_local_archive.dart';

/// 本机书库的 [LibraryRepository] 实现（零网络依赖，全走本地 SQLite 与受管沙盒）。
final class LocalLibraryRepository implements LibraryRepository {
  LocalLibraryRepository(this._db, this._storage, {int coverCacheCapacity = 64})
    : _covers = ByteLruCache(capacity: coverCacheCapacity);

  final ProgressDatabase _db;
  final LocalComicsStorage _storage;
  final ByteLruCache _covers;

  void evictCoverCache({String? seriesId, String? bookId}) {
    if (seriesId == null && bookId == null) {
      _covers.clear();
      return;
    }
    // ByteLruCache 支持容量清理；指定系列或书籍封面变更时直接清空小容量封面缓存最稳妥。
    _covers.clear();
  }

  @override
  Future<List<Library>> libraries() async => const <Library>[];

  @override
  Future<PageResult<Series>> series({
    String? libraryId,
    String? query,
    int page = 0,
    int size = 30,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
    String? tag,
  }) {
    return _db.queryLocalSeries(
      query: query,
      page: page,
      size: size,
      sort: sort,
      readStatus: readStatus,
      tag: tag,
    );
  }

  @override
  Future<Series?> seriesById(String seriesId) => _db.localSeriesById(seriesId);

  @override
  Future<Book?> book(String bookId) => _db.localBookById(bookId);

  @override
  Future<PageResult<Book>> searchBooks(
    String query, {
    int page = 0,
    int size = 20,
  }) {
    return _db.searchLocalBooks(query, page: page, size: size);
  }

  @override
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
    BooksSort? sort,
    SeriesReadStatus? readStatus,
  }) {
    return _db.queryLocalSeriesBooks(
      seriesId,
      page: page,
      size: size,
      sort: sort,
      readStatus: readStatus,
    );
  }

  @override
  Future<PageResult<Book>> ondeck({int size = 20}) =>
      _db.localOndeck(size: size);

  @override
  Future<Uint8List?> seriesCover(String seriesId) async {
    final key = 'series:$seriesId';
    final cached = _covers.get(key);
    if (cached != null) return cached;

    final row = await _db.localSeriesRowById(seriesId);
    if (row == null) return null;

    if (row.customCoverPath != null && row.customCoverPath!.isNotEmpty) {
      final customBytes = await _readRelativeFileOrNull(row.customCoverPath!);
      if (customBytes != null && customBytes.isNotEmpty) {
        _covers.put(key, customBytes);
        return customBytes;
      }
    }

    String? targetBookId = row.coverBookId;
    if (targetBookId == null) {
      final firstPage = await _db.queryLocalSeriesBooks(seriesId, size: 1);
      if (firstPage.items.isNotEmpty) {
        targetBookId = firstPage.items.first.id;
      }
    }
    if (targetBookId == null) return null;

    final bytes = await bookCover(targetBookId);
    if (bytes != null) {
      _covers.put(key, bytes);
    }
    return bytes;
  }

  @override
  Future<Uint8List?> bookCover(String bookId) async {
    final key = 'book:$bookId';
    final cached = _covers.get(key);
    if (cached != null) return cached;

    final row = await _db.localBookRowById(bookId);
    if (row == null) return null;

    if (row.coverThumbPath != null && row.coverThumbPath!.isNotEmpty) {
      final thumbBytes = await _readRelativeFileOrNull(row.coverThumbPath!);
      if (thumbBytes != null && thumbBytes.isNotEmpty) {
        _covers.put(key, thumbBytes);
        return thumbBytes;
      }
    }

    // 缩略图尚未落盘或被清理时，回退提取该书第 1 页字节作为封面。
    final fallback = await _extractFirstPageOrNull(row);
    if (fallback != null && fallback.isNotEmpty) {
      _covers.put(key, fallback);
    }
    return fallback;
  }

  Future<Uint8List?> _readRelativeFileOrNull(String relativePath) async {
    try {
      final file = await _storage.resolveFile(relativePath);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on ArchiveException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<Uint8List?> _extractFirstPageOrNull(LocalBooksRow row) async {
    ComicArchiveReader? reader;
    try {
      if (row.storageKind == 'folder') {
        final dir = await _storage.resolveDirectory(row.relativePath);
        reader = await FolderComicReader.open(dir, sniffDimensions: false);
      } else {
        final file = await _storage.resolveFile(row.relativePath);
        reader = await ZipComicReader.open(
          await FileByteSource.open(file),
          sniffDimensions: false,
        );
      }
      return await reader.readPage(1);
    } on Object {
      return null;
    } finally {
      await reader?.close();
    }
  }
}
