import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 下载队列持久化失败回调（便于日志与单测观测，不静默吞错）。
typedef QueuePersistenceErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

/// 下载队列的异步写盘辅助（与控制器状态机解耦）。
class DownloadQueuePersistence {
  const DownloadQueuePersistence(this._db, {this.onError});

  final HttpCacheDatabase _db;
  final QueuePersistenceErrorHandler? onError;

  void _fire(String op, Future<Object?> work) {
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('DownloadQueuePersistence.$op failed: $error');
          onError?.call(error, stackTrace);
        },
      ),
    );
  }

  Future<bool> isDownloaded(String bookId, {required String scope}) async {
    try {
      return await _db.download(bookId, scope: scope) != null;
    } on Object catch (error, stackTrace) {
      debugPrint('DownloadQueuePersistence.isDownloaded failed: $error');
      onError?.call(error, stackTrace);
      // 查不了按未下完恢复。
      return false;
    }
  }

  /// 过滤持久化队列行：已下完的顺手清掉残留行，未下完的还原为带远端 `sourceKey` 的 [Book]。
  Future<List<Book>> filterPendingEntries(
    List<DownloadQueueEntry> entries, {
    required String fallbackScope,
    required bool Function(String bookId) isAlreadyTracked,
  }) async {
    final pending = <Book>[];
    for (final entry in entries) {
      if (isAlreadyTracked(entry.bookId)) continue;
      final entryScope = entry.scope.isNotEmpty ? entry.scope : fallbackScope;
      if (await isDownloaded(entry.bookId, scope: entryScope)) {
        dequeue(entry.bookId, scope: entryScope);
        continue;
      }
      pending.add(toBook(entry, fallbackScope: fallbackScope));
    }
    return pending;
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
    'enqueue',
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
    'markActive',
    _db.updateQueueEntry(
      scope: scope,
      bookId: bookId,
      state: 'active',
      done: done,
      total: total,
    ),
  );

  void dequeue(String bookId, {required String scope}) =>
      _fire('dequeue', _db.dequeueDownload(bookId, scope: scope));

  /// 清空持久化队列；`scope == null` 时清空全部分区，防止其他分区记录下次切回时复活。
  void clear({String? scope}) =>
      _fire('clear', _db.clearDownloadQueue(scope: scope));
}
