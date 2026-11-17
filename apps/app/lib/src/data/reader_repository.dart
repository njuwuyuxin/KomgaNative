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

  /// 只负责**把进度发给服务端**。落盘与重试在 `ProgressSyncService`，
  /// 这里不再"直连 PATCH 一发了之"（断网就会丢）。
  Future<void> uploadProgress(
    String bookId, {
    required int page,
    required bool completed,
  });
}

class KomgaReaderRepository implements ReaderRepository {
  KomgaReaderRepository(this._session, this._sync, {int pageCacheCapacity = 8})
    : _pages = ByteLruCache(capacity: pageCacheCapacity);

  final KomgaSession _session;
  final ProgressSyncService _sync;

  /// 页图单张通常几百 KB 到 2 MB，缓存 8 张足够覆盖"前后翻页"而不会吃爆内存。
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
