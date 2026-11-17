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
///
/// 为什么不直接复用"读过的页自动缓存"：那是**被动**的，用户无法预期
/// "这本书断网能不能读"。下载是显式意图：开始、看进度、可取消、可删除。
///
/// 抽成接口是为了单测能脱离 KomgaSession（用两个闭包喂页列表与页图），
/// 而不是为"以后可能换实现"。
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

  /// 页列表（含页码/尺寸）。
  final Future<List<PageInfo>> Function(String bookId) pages;

  /// 单页图字节（会顺带写进 HTTP 缓存，所以离线可直接读）。
  final Future<Uint8List> Function(String bookId, int page) pageImage;

  final HttpCacheDatabase db;
  final String scope;

  /// 进行中的下载：bookId → 是否已请求取消。
  final Map<String, bool> _cancelFlags = <String, bool>{};

  @override
  Future<DownloadedBook?> downloaded(String bookId) => db.download(bookId);

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async {
    if (await db.download(book.id) != null) return false;

    final list = await pages(book.id);
    if (list.isEmpty) return false;

    _cancelFlags[book.id] = false;
    var progress = DownloadProgress(done: 0, total: list.length);
    var bytes = 0;
    try {
      onProgress(progress);
      for (final page in list) {
        if (_cancelFlags[book.id] ?? false) return false;
        final data = await pageImage(book.id, page.number);
        bytes += data.length;
        progress = progress.advance();
        onProgress(progress);
      }
      await db.markDownloaded(
        bookId: book.id,
        seriesId: book.seriesId,
        pageCount: list.length,
        bytes: bytes,
      );
      return true;
    } finally {
      _cancelFlags.remove(book.id);
    }
  }

  @override
  void cancel(String bookId) {
    if (_cancelFlags.containsKey(bookId)) _cancelFlags[bookId] = true;
  }

  @override
  Future<void> delete(Book book) async {
    await db.removeDownload(book.id);
    await db.deleteCachedPages(scope: scope, bookId: book.id);
  }
}
