import 'dart:typed_data';

import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/byte_cache.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 阅读器的数据来源。
///
/// 和书架分开是因为语义不同：**页图是内容本身**，加载失败必须报错让用户重试；
/// 封面只是装饰，失败就退回占位图。
abstract interface class ReaderRepository {
  /// 书的基本信息（页数、阅读进度）。书被删时返回 null。
  ///
  /// 返回的 `readProgress` 已经叠加过**本地未提交进度**：断网读完一章再打开，
  /// 位置不会退回服务端的旧值。
  Future<Book?> book(String bookId);

  /// 每一页的尺寸/字节数；页码与 [PageInfo.number] 都是 1 基。
  Future<List<PageInfo>> pages(String bookId);

  /// 第 [page] 页的图片字节（1 基）。
  Future<Uint8List> pageImage(String bookId, int page);

  /// 第 [page] 页的字节**此刻**在不在内存里（1 基）；不在返回 null。
  ///
  /// 这是给"绘制第一帧"用的同步查询：翻回去、连翻时字节早就在 LRU 里，
  /// 直接画就行。只走 `pageImage` 的话要多等一个异步回合，
  /// 那一帧的 loading 就是用户看到的"闪一下"。
  Uint8List? cachedPageImage(String bookId, int page);

  /// 只负责**把进度发给服务端**。落盘与重试在 `ProgressSyncService`，
  /// 这里不再"直连 PATCH 一发了之"（断网就会丢）。
  Future<void> uploadProgress(
    String bookId, {
    required int page,
    required bool completed,
  });
}

class KomgaReaderRepository implements ReaderRepository {
  /// 页图缓存张数，默认 16。
  ///
  /// 单张几百 KB 到 2 MB，16 张约 10–30 MB——比"把整本留在内存里"便宜得多，
  /// 又足够覆盖"翻过去再翻回来"。再多就该靠磁盘缓存（离线）而不是内存了。
  static const int defaultPageCacheCapacity = 16;

  KomgaReaderRepository(
    this._session,
    this._sync, {
    int pageCacheCapacity = defaultPageCacheCapacity,
  }) : _pages = ByteLruCache(capacity: pageCacheCapacity);

  final KomgaSession _session;
  final ProgressSyncService _sync;

  final ByteLruCache _pages;

  @override
  Future<Book?> book(String bookId) async {
    try {
      final book = await _session.fetchBook(bookId);
      return await _sync.overlayOne(book);
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
  Future<Uint8List> pageImage(String bookId, int page) async {
    final key = '$bookId#$page';
    final cached = _pages.get(key);
    if (cached != null) return cached;

    try {
      final bytes = await _session.fetchPageImage(bookId, page);
      _pages.put(key, bytes);
      return bytes;
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Uint8List? cachedPageImage(String bookId, int page) =>
      _pages.peek('$bookId#$page');

  @override
  Future<void> uploadProgress(
    String bookId, {
    required int page,
    required bool completed,
  }) async {
    try {
      await _session.updateReadProgress(
        bookId,
        page: page,
        completed: completed,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }
}
