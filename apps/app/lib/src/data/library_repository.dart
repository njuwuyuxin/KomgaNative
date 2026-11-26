import 'dart:typed_data';

import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/byte_cache.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';

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

  /// "继续阅读"：优先返回在读中的书（`IN_PROGRESS`），再用 Komga `ondeck`（下一卷未读）兜底。
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

  String get _sourceKey => _session.address.baseUrl;

  PageResult<Series> _tagSeriesPage(PageResult<Series> page) =>
      PageResult<Series>(
        items: <Series>[for (final s in page.items) s.withSource(_sourceKey)],
        totalElements: page.totalElements,
        page: page.page,
        size: page.size,
      );

  PageResult<Book> _tagBooksPage(PageResult<Book> page) => PageResult<Book>(
    items: <Book>[for (final b in page.items) b.withSource(_sourceKey)],
    totalElements: page.totalElements,
    page: page.page,
    size: page.size,
  );

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
      final result = await _session.fetchSeries(
        libraryId: libraryId,
        search: query,
        page: page,
        size: size,
        sort: sort,
        readStatus: readStatus,
        tag: tag,
      );
      return _tagSeriesPage(result);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<Series?> seriesById(String seriesId) async {
    try {
      final fetched = await _session.fetchSeriesById(seriesId);
      return fetched?.withSource(_sourceKey);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<Book?> book(String bookId) async {
    try {
      final fetched = await _session.fetchBook(bookId);
      final overlaid = await _sync.overlayOne(fetched);
      return overlaid?.withSource(_sourceKey);
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
      return _tagBooksPage(await overlayBooksPage(_sync, result));
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
      return _tagBooksPage(await overlayBooksPage(_sync, result));
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<Book>> ondeck({int size = 20}) async {
    // 先尽力把本地积压的进度推上服务端，避免刚退出阅读器就拉到旧列表；
    // 断网时 flush 内部吞掉 ShelfFailure 立即返回，不阻塞离线回退。
    await _sync.flush();

    final PageResult<Book> inProgressRaw;
    try {
      inProgressRaw = await _session.fetchInProgressBooks(size: size);
    } on KomgaError catch (error) {
      if (error is KomgaNetworkError || error is KomgaServerError) {
        final localOnly = await _sync.pendingInProgressBooks(
          loadBook: _tryLoadBook,
        );
        if (localOnly.isNotEmpty) {
          final items = localOnly
              .take(size)
              .map((Book b) => b.withSource(_sourceKey))
              .toList(growable: false);
          return PageResult<Book>(
            items: items,
            totalElements: localOnly.length,
            page: 0,
            size: size,
          );
        }
      }
      throw shelfFailureOf(error);
    }

    PageResult<Book>? nextUnreadRaw;
    try {
      nextUnreadRaw = await _session.fetchOndeck(size: size);
    } on KomgaError catch (error) {
      if (inProgressRaw.items.isEmpty) {
        final localOnly = await _sync.pendingInProgressBooks(
          loadBook: _tryLoadBook,
        );
        if (localOnly.isEmpty) throw shelfFailureOf(error);
      }
    }

    final inProgressOverlay = await _sync.overlay(inProgressRaw.items);
    final nextOverlay = nextUnreadRaw == null
        ? const <Book>[]
        : await _sync.overlay(nextUnreadRaw.items);
    final pendingLocal = await _sync.pendingInProgressBooks(
      loadBook: _tryLoadBook,
    );

    final merged = _mergeContinueReading(
      pendingLocal: pendingLocal,
      inProgress: inProgressOverlay,
      ondeck: nextOverlay,
    );
    final items = merged
        .take(size)
        .map((Book b) => b.withSource(_sourceKey))
        .toList(growable: false);
    return PageResult<Book>(
      items: items,
      totalElements: merged.length,
      page: 0,
      size: size,
    );
  }

  Future<Book?> _tryLoadBook(String bookId) async {
    try {
      return await _session.fetchBook(bookId);
    } on KomgaError {
      return null;
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

List<Book> _mergeContinueReading({
  required List<Book> pendingLocal,
  required List<Book> inProgress,
  required List<Book> ondeck,
}) {
  final seen = <String>{};
  final active = <Book>[];
  final upNext = <Book>[];

  for (final book in pendingLocal) {
    if (!book.isCompleted && !book.isUnread && seen.add(book.id)) {
      active.add(book);
    }
  }
  for (final book in inProgress) {
    if (!book.isCompleted && !book.isUnread && seen.add(book.id)) {
      active.add(book);
    }
  }

  final activeSeries = <String>{for (final b in active) b.seriesId};
  for (final book in ondeck) {
    if (book.isCompleted || !seen.add(book.id)) continue;
    if (!book.isUnread) {
      active.add(book);
      activeSeries.add(book.seriesId);
    } else if (!activeSeries.contains(book.seriesId)) {
      upNext.add(book);
    }
  }
  return <Book>[...active, ...upNext];
}
