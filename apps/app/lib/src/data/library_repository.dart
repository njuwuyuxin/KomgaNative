import 'dart:typed_data';

import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/byte_cache.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 书架/系列详情的数据来源。
///
/// UI 只认这个接口：`screens/**` 与 `widgets/**` 都不能 import `komga_api`，
/// 网络细节全部关在实现里；测试用假实现替换，黄金图不联网。
abstract interface class LibraryRepository {
  Future<List<Library>> libraries();

  /// 系列分页。`query` 为空表示不搜索。
  Future<PageResult<Series>> series({
    String? libraryId,
    String? query,
    int page = 0,
    int size = 30,
  });

  /// 单个系列；已被删除时返回 null。
  Future<Series?> seriesById(String seriesId);

  /// 系列下的书。默认一次抓 100 本（多数系列够用，超出部分 UI 会明说）。
  Future<PageResult<Book>> books(
    String seriesId, {
    int page = 0,
    int size = 100,
  });

  /// 系列封面。返回 `null` 表示"没有封面"——装饰性资源**不允许**让整页报错。
  Future<Uint8List?> seriesCover(String seriesId);

  Future<Uint8List?> bookCover(String bookId);
}

/// 真实实现：包一层 [KomgaSession]，把 `KomgaError` 翻成 [ShelfFailure]。
class KomgaLibraryRepository implements LibraryRepository {
  KomgaLibraryRepository(this._session, {int coverCacheCapacity = 48})
    : _covers = ByteLruCache(capacity: coverCacheCapacity);

  final KomgaSession _session;
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
  }) async {
    try {
      return await _session.fetchSeries(
        libraryId: libraryId,
        search: query,
        page: page,
        size: size,
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
      return await _session.fetchSeriesBooks(seriesId, page: page, size: size);
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
