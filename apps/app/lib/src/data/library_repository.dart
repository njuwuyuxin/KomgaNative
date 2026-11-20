import 'dart:typed_data';

import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/byte_cache.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 书架与目录查询限界上下文（库、系列、书籍目录、搜索、继续阅读、封面，ARC-09）。
///
/// 收藏集/阅读列表归 [CollectionsRepository]，已读/未读状态变更归 [ReadStatusRepository]。
abstract interface class LibraryRepository {
  Future<List<Library>> libraries();

  /// 系列分页。`query` 为空表示不搜索；`sort` / `readStatus` 为空用服务端默认。
  Future<PageResult<Series>> series({
    String? libraryId,
    String? query,
    int page = 0,
    int size = 30,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
    String? tag,
  });

  /// 单个系列；已被删除时返回 null。
  Future<Series?> seriesById(String seriesId);

  /// 单本书（下载管理页用；不存在时返回 null）。
  Future<Book?> book(String bookId);

  /// 全局书搜索（UI-P3-9）。
  Future<PageResult<Book>> searchBooks(
    String query, {
    int page = 0,
    int size = 20,
  });

  /// 系列下的书。
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
    BooksSort? sort,
    SeriesReadStatus? readStatus,
  });

  /// "继续阅读"（Komga 的 ondeck：在读过、还没读完的书）。
  Future<PageResult<Book>> ondeck({int size = 20});

  /// 系列封面。返回 `null` 表示"没有封面"——装饰性资源**不允许**让整页报错。
  Future<Uint8List?> seriesCover(String seriesId);

  Future<Uint8List?> bookCover(String bookId);
}

/// 真实实现：共享 [KomgaSession]，把 `KomgaError` 翻成 [ShelfFailure]，并叠加本地进度。
class KomgaLibraryRepository implements LibraryRepository {
  KomgaLibraryRepository(
    this._session,
    this._sync, {
    int coverCacheCapacity = 48,
  }) : _covers = ByteLruCache(capacity: coverCacheCapacity);

  final KomgaSession _session;
  final ProgressSyncService _sync;
  final ByteLruCache _covers;

  /// 测试诊断用：暴露底层会话引用以验证连接池共享。
  KomgaSession get debugSession => _session;

  @override
  Future<List<Library>> libraries() async {
    try {
      return await _session.fetchLibraries();
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<Series>> series({
    String? libraryId,
    String? query,
    int page = 0,
    int size = 30,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
    String? tag,
  }) async {
    try {
      return await _session.fetchSeries(
        libraryId: libraryId,
        search: query,
        page: page,
        size: size,
        sort: sort,
        readStatus: readStatus,
        tag: tag,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<Series?> seriesById(String seriesId) async {
    try {
      return await _session.fetchSeriesById(seriesId);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<Book?> book(String bookId) async {
    try {
      final fetched = await _session.fetchBook(bookId);
      return await _sync.overlayOne(fetched);
    } on KomgaNotFoundError {
      return null;
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<Book>> searchBooks(
    String query, {
    int page = 0,
    int size = 20,
  }) async {
    try {
      final result = await _session.searchBooks(query, page: page, size: size);
      return await overlayBooksPage(_sync, result);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
    BooksSort? sort,
    SeriesReadStatus? readStatus,
  }) async {
    try {
      final result = await _session.fetchSeriesBooks(
        seriesId,
        page: page,
        size: size,
        sort: sort,
        readStatus: readStatus,
      );
      return await overlayBooksPage(_sync, result);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<Book>> ondeck({int size = 20}) async {
    try {
      final result = await _session.fetchOndeck(size: size);
      return await overlayBooksPage(_sync, result);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<Uint8List?> seriesCover(String seriesId) =>
      _cover('series:$seriesId', () => _session.fetchSeriesThumbnail(seriesId));

  @override
  Future<Uint8List?> bookCover(String bookId) =>
      _cover('book:$bookId', () => _session.fetchBookThumbnail(bookId));

  Future<Uint8List?> _cover(
    String cacheKey,
    Future<Uint8List> Function() load,
  ) async {
    final cached = _covers.get(cacheKey);
    if (cached != null) return cached;

    try {
      final bytes = await load();
      _covers.put(cacheKey, bytes);
      return bytes;
    } on KomgaError {
      return null;
    }
  }
}

/// 书籍分页结果的本地进度叠加辅助函数（供目录仓库与阅读列表仓库共用）。
Future<PageResult<Book>> overlayBooksPage(
  ProgressSyncService sync,
  PageResult<Book> result,
) async => PageResult<Book>(
  items: await sync.overlay(result.items),
  totalElements: result.totalElements,
  page: result.page,
  size: result.size,
);
