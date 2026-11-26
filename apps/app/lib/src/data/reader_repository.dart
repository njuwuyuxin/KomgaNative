import 'dart:typed_data';

import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/byte_cache.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';

/// 阅读器的数据来源（书元信息、页列表、页图与内存页图缓存，ARC-09）。
abstract interface class ReaderRepository {
  /// 书的基本信息（页数、阅读进度）。书被删时返回 null。
  Future<Book?> book(String bookId);

  /// 每一页的尺寸/字节数；页码与 [PageInfo.number] 都是 1 基。
  Future<List<PageInfo>> pages(String bookId);

  /// 第 [page] 页的图片字节（1 基）。
  Future<Uint8List> pageImage(String bookId, int page);

  /// 第 [page] 页的字节**此刻**在不在内存里（1 基）；不在返回 null。
  Uint8List? cachedPageImage(String bookId, int page);

  /// 第 [page] 页的低精度缩略图字节（1 基，优先服务端 300px JPEG，离线已下载时回退原图）。
  Future<Uint8List> pageThumbnail(String bookId, int page);

  /// 第 [page] 页的缩略图字节**此刻**在不在内存里（1 基）；不在返回 null。
  Uint8List? cachedPageThumbnail(String bookId, int page);
}

class KomgaReaderRepository implements ReaderRepository {
  /// 页图字节内存 LRU 容量。
  ///
  /// 需同时容纳 `ReaderPreloader`（前后共 6 屏 ≈ 双页 12 页）、底栏缩略图滑条
  /// 可见项以及最近翻过的历史跨页；太小（如早期 16）会在打开缩略图滑条或连续翻几屏后
  /// 把刚读过的页挤出内存，导致往回翻时重拉网络并丢失 `ImageCache` 键引用。
  static const int defaultPageCacheCapacity = 64;

  /// 页缩略图字节内存 LRU 容量：单张 300px JPEG 仅约 10–25 KB，独立缓存不挤占原图 LRU。
  static const int defaultThumbnailCacheCapacity = 128;

  KomgaReaderRepository(
    this._session,
    this._sync, {
    int pageCacheCapacity = defaultPageCacheCapacity,
    int thumbnailCacheCapacity = defaultThumbnailCacheCapacity,
  }) : _pages = ByteLruCache(capacity: pageCacheCapacity),
       _thumbnails = ByteLruCache(capacity: thumbnailCacheCapacity);

  final KomgaSession _session;
  final ProgressSyncService _sync;
  final ByteLruCache _pages;
  final ByteLruCache _thumbnails;
  final Map<String, Future<Uint8List>> _inFlight =
      <String, Future<Uint8List>>{};
  final Map<String, Future<Uint8List>> _thumbInFlight =
      <String, Future<Uint8List>>{};

  KomgaSession get debugSession => _session;

  @override
  Future<Book?> book(String bookId) async {
    try {
      final scope = _session.address.baseUrl;
      final book = await _session.fetchBook(bookId);
      final overlaid = await _sync.overlayOne(book, scope: scope);
      return overlaid?.withSource(scope);
    } on KomgaNotFoundError {
      return null;
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<List<PageInfo>> pages(String bookId) async {
    try {
      return await _session.fetchBookPages(bookId);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<Uint8List> pageImage(String bookId, int page) {
    final key = '$bookId#$page';
    final cached = _pages.get(key);
    if (cached != null) return Future<Uint8List>.value(cached);
    // 合并同页并发请求：避免预取、页面显示、缩略图与卷页解码并发拉取产生多份
    // 不同引用的 Uint8List，保证 `MemoryImage(bytes)` 在 `ImageCache` 里始终命中同一键。
    return _inFlight[key] ??= _fetchAndCachePage(key, bookId, page);
  }

  Future<Uint8List> _fetchAndCachePage(
    String key,
    String bookId,
    int page,
  ) async {
    try {
      final bytes = await _session.fetchPageImage(bookId, page);
      _pages.put(key, bytes);
      return bytes;
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    } finally {
      _inFlight.remove(key)?.ignore();
    }
  }

  @override
  Uint8List? cachedPageImage(String bookId, int page) =>
      _pages.peek('$bookId#$page');

  @override
  Future<Uint8List> pageThumbnail(String bookId, int page) {
    final key = '$bookId#$page';
    final cached = _thumbnails.get(key);
    if (cached != null) return Future<Uint8List>.value(cached);
    return _thumbInFlight[key] ??= _fetchAndCacheThumbnail(key, bookId, page);
  }

  Future<Uint8List> _fetchAndCacheThumbnail(
    String key,
    String bookId,
    int page,
  ) async {
    try {
      final bytes = await _session.fetchPageThumbnail(bookId, page);
      _thumbnails.put(key, bytes);
      return bytes;
    } on KomgaError catch (error) {
      // 整本离线下载只缓存了原图页，未拉取缩略图；断网时自动回退到原图缓存。
      final fullCached = _pages.peek(key);
      if (fullCached != null) return fullCached;
      if (error is KomgaNetworkError || error is KomgaServerError) {
        try {
          return await pageImage(bookId, page);
        } on ShelfFailure {
          throw shelfFailureOf(error);
        }
      }
      throw shelfFailureOf(error);
    } finally {
      _thumbInFlight.remove(key)?.ignore();
    }
  }

  @override
  Uint8List? cachedPageThumbnail(String bookId, int page) =>
      _thumbnails.peek('$bookId#$page');
}
