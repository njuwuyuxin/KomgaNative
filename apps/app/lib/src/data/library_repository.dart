import 'dart:typed_data';

import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/byte_cache.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 书架/系列详情的数据来源。
///
/// UI 只认这个接口：`screens/**` 与 `widgets/**` 都不能 import `komga_api`，
/// 网络细节全部关在实现里；测试用假实现替换，黄金图不联网。
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
  });

  /// 单个系列；已被删除时返回 null。
  Future<Series?> seriesById(String seriesId);

  /// 系列下的书。默认一次抓 100 本（多数系列够用，超出部分 UI 会明说）。
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
  });

  /// "继续阅读"（Komga 的 ondeck：在读过、还没读完的书）。
  Future<PageResult<Book>> ondeck({int size = 20});

  /// 系列封面。返回 `null` 表示"没有封面"——装饰性资源**不允许**让整页报错。
  Future<Uint8List?> seriesCover(String seriesId);

  Future<Uint8List?> bookCover(String bookId);
}

/// 真实实现：包一层 [KomgaSession]，把 `KomgaError` 翻成 [ShelfFailure]。
///
/// 书列表会用 [ProgressSyncService] 做一次"本地进度叠加"：断网时读到的进度
/// 还没提交，但用户看到的必须是**自己刚读到的位置**，不是服务端的旧值。
class KomgaLibraryRepository implements LibraryRepository {
  KomgaLibraryRepository(
    this._session,
    this._sync, {
    int coverCacheCapacity = 48,
  }) : _covers = ByteLruCache(capacity: coverCacheCapacity);

  final KomgaSession _session;
  final ProgressSyncService _sync;
  final ByteLruCache _covers;

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
  }) async {
    try {
      return await _session.fetchSeries(
        libraryId: libraryId,
        search: query,
        page: page,
        size: size,
        sort: sort,
        readStatus: readStatus,
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
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
  }) async {
    try {
      final result = await _session.fetchSeriesBooks(
        seriesId,
        page: page,
        size: size,
      );
      return PageResult<Book>(
        items: await _sync.overlay(result.items),
        totalElements: result.totalElements,
        page: result.page,
        size: result.size,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  /// "继续阅读"：Komga 的 ondeck（在读过、还没读完的书）。
  ///
  /// 同样叠加本地未提交进度：断网读完最后一页但还没补交时，书架不该还显示旧页码。
  @override
  Future<PageResult<Book>> ondeck({int size = 20}) async {
    try {
      final result = await _session.fetchOndeck(size: size);
      return PageResult<Book>(
        items: await _sync.overlay(result.items),
        totalElements: result.totalElements,
        page: result.page,
        size: result.size,
      );
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
      // 封面失败不抛：书架照常显示占位图，用户还能点进去读。
      return null;
    }
  }
}
