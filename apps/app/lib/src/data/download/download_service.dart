import 'dart:typed_data';

import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';

/// 整本下载的进度（0 基已完成页数）。
class DownloadProgress {
  const DownloadProgress({required this.done, required this.total});

  final int done;
  final int total;

  /// 页数未知时返回 null（UI 显示不确定进度）。
  double? get fraction => total <= 0 ? null : done / total;

  DownloadProgress advance() => DownloadProgress(done: done + 1, total: total);
}

/// 整本下载。
abstract interface class DownloadService {
  Future<DownloadedBook?> downloaded(String bookId);

  /// 下载整本。已完成返回 false（幂等）。取消时返回 false，已下载的页保留。
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  });

  /// 请求取消（在页与页之间生效：单页请求不中断，避免把连接搞坏）。
  void cancel(String bookId);

  /// 删除下载记录 **和** 已缓存的页图。
  Future<void> delete(Book book);
}

class KomgaDownloadService implements DownloadService {
  KomgaDownloadService({
    required this.pages,
    required this.pageImage,
    required this.db,
    required this.scope,
  });

  final Future<List<PageInfo>> Function(String bookId) pages;
  final Future<Uint8List> Function(String bookId, int page) pageImage;
  final HttpCacheDatabase db;
  final String scope;

  final Map<String, bool> _cancelFlags = <String, bool>{};

  @override
  Future<DownloadedBook?> downloaded(String bookId) =>
      db.download(bookId, scope: scope);

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    if (await db.download(book.id, scope: scope) != null) return false;

    final list = await pages(book.id);
    if (list.isEmpty) return false;

    _cancelFlags[book.id] = false;
    var progress = DownloadProgress(done: 0, total: list.length);
    var bytes = 0;
    var completed = false;
    try {
      onProgress(progress);
      for (final page in list) {
        if (_cancelFlags[book.id] ?? false) return false;
        final data = await pageImage(book.id, page.number);
        // 逐页立即钉住：即使单书总大小超过被动 LRU 预算，后续页也不会把前面的页挤掉。
        await db.setBookPagesPinned(
          scope: scope,
          bookId: book.id,
          pinned: true,
        );
        bytes += data.length;
        progress = progress.advance();
        onProgress(progress);
      }
      await db.markDownloaded(
        scope: scope,
        bookId: book.id,
        seriesId: book.seriesId,
        pageCount: list.length,
        bytes: bytes,
      );
      completed = true;
      return true;
    } finally {
      _cancelFlags.remove(book.id);
      if (!completed) {
        // 取消或中途失败时尚未成为"已下载"，解除钉住以回归普通被动缓存策略。
        await db.setBookPagesPinned(
          scope: scope,
          bookId: book.id,
          pinned: false,
        );
      }
    }
  }

  @override
  void cancel(String bookId) {
    if (_cancelFlags.containsKey(bookId)) _cancelFlags[bookId] = true;
  }

  @override
  Future<void> delete(Book book) async {
    await db.removeDownload(book.id, scope: scope);
    await db.deleteCachedPages(scope: scope, bookId: book.id);
  }
}
