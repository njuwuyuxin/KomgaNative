import 'dart:typed_data';

import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cover_cache.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 书架数据来源。
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

  /// 系列封面。
  ///
  /// 返回 `null` 表示"没有封面"——封面是装饰，**不允许**因为它让整页报错。
  Future<Uint8List?> seriesCover(String seriesId);
}

/// 真实实现：包一层 [KomgaSession]，把 `KomgaError` 翻成 [ShelfFailure]。
class KomgaLibraryRepository implements LibraryRepository {
  KomgaLibraryRepository(this._session, {int coverCacheCapacity = 48})
    : _covers = CoverCache(capacity: coverCacheCapacity);

  final KomgaSession _session;
  final CoverCache _covers;

  CoverCache get coverCache => _covers;

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
  Future<Uint8List?> seriesCover(String seriesId) async {
    final cached = _covers.get(seriesId);
    if (cached != null) return cached;

    try {
      final bytes = await _session.fetchSeriesThumbnail(seriesId);
      _covers.put(seriesId, bytes);
      return bytes;
    } on KomgaError {
      // 封面失败不抛：书架照常显示占位图，用户还能点进去读书。
      return null;
    }
  }
}
