import 'dart:async';

import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';

/// 下载队列的异步写盘辅助（与控制器状态机解耦）。
class DownloadQueuePersistence {
  const DownloadQueuePersistence(this._db);

  final HttpCacheDatabase _db;

  void _fire(Future<void> work) => unawaited(work.catchError((Object _) {}));

  Future<bool> isDownloaded(String bookId, {required String scope}) async {
    try {
      return await _db.download(bookId, scope: scope) != null;
    } on Object {
      // 查不了按未下完恢复。
      return false;
    }
  }

  /// 将持久化队列行还原为携带远端 `sourceKey` 的领域 [Book]。
  Book toBook(DownloadQueueEntry entry, {required String fallbackScope}) {
    final bookScope = entry.scope.isNotEmpty ? entry.scope : fallbackScope;
    return Book(
      id: entry.bookId,
      seriesId: entry.seriesId,
      name: entry.name,
      number: entry.number,
      pagesCount: entry.pagesCount,
      sourceKey: bookScope.isNotEmpty ? bookScope : kLocalSourceKey,
    );
  }

  void enqueue(Book book, {required String scope}) => _fire(
    _db.enqueueDownload(
      scope: scope,
      bookId: book.id,
      seriesId: book.seriesId,
      name: book.name,
      number: book.number,
      pagesCount: book.pagesCount,
    ),
  );

  void markActive(String scope, String bookId, int done, int total) => _fire(
    _db.updateQueueEntry(
      scope: scope,
      bookId: bookId,
      state: 'active',
      done: done,
      total: total,
    ),
  );

  void dequeue(String bookId, {required String scope}) =>
      _fire(_db.dequeueDownload(bookId, scope: scope));

  void clear({required String scope}) =>
      _fire(_db.clearDownloadQueue(scope: scope));
}
