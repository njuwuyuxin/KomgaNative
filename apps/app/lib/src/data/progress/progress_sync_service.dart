import 'dart:async';

import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/progress/progress_store.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu_sync/yomu_sync.dart';

/// 单服进度上传接口（单测便捷入口）。
typedef ProgressUpload = Future<void> Function(ProgressTarget target);

/// 带服务器分区校验的进度上传接口（ARC-07）。
typedef ScopedProgressUpload = Future<void> Function(
  String scope,
  ProgressTarget target,
);

/// 进度同步：本地按服务器分区先写，再按所属分区尽力提交至对应源。
class ProgressSyncService {
  ProgressSyncService({
    required ProgressStore store,
    ProgressUpload? upload,
    ScopedProgressUpload? scopedUpload,
    String Function()? activeScope,
  }) : assert(upload != null || scopedUpload != null, '必须提供上传实现'),
       _store = store,
       _activeScope = activeScope ?? (() => ''),
       _upload =
           scopedUpload ??
           ((String _, ProgressTarget target) => upload!(target));

  final ProgressStore _store;
  final String Function() _activeScope;
  final ScopedProgressUpload _upload;

  Future<void>? _inFlight;
  final Set<String> _pendingFlushScopes = <String>{};
  final Set<String> _authBlockedScopes = <String>{};
  static const int _maxKnownBooksPerScope = 256;
  final Map<String, Map<String, Book>> _knownBooks =
      <String, Map<String, Book>>{};

  ProgressStore get store => _store;

  /// 记住一本书的基础元信息（供离线/同步失败时把本地 pending 书补进"继续阅读"）。
  void noteBook(Book book, {String? scope}) {
    final key = scope ?? _activeScope();
    final bucket = _knownBooks.putIfAbsent(key, () => <String, Book>{});
    bucket
      ..remove(book.id)
      ..[book.id] = book;
    if (bucket.length > _maxKnownBooksPerScope) {
      bucket.remove(bucket.keys.first);
    }
  }

  /// 用户显式改了阅读状态（标记已读/未读）后调用：本地那份 pending 已过期。
  Future<void> forceAdopt(
    String bookId,
    ReadProgress? remote, {
    String? scope,
  }) => _store.forceAdopt(bookId, remote, scope: scope ?? _activeScope());

  /// 记一页进度：
  /// - 本机源（[scope] 为 [kLocalSourceKey]）直接落盘至 `kLocalSourceKey`（`pendingSeq = null`），不入远程队列；
  /// - 远程服务器先落入对应 [scope] 分区，再针对该分区触发冲洗提交（不阻塞调用方）。
  Future<void> save(
    String bookId, {
    required int page,
    required bool completed,
    String? scope,
  }) async {
    final effectiveScope = (scope != null && scope.isNotEmpty)
        ? scope
        : _activeScope();
    final isLocalTarget =
        effectiveScope == kLocalSourceKey ||
        (effectiveScope.isEmpty && bookId.startsWith('local:'));
    if (isLocalTarget) {
      await _store.forceAdopt(
        bookId,
        ReadProgress(
          page: page,
          completed: completed,
          lastModified: DateTime.now().toUtc(),
        ),
        scope: kLocalSourceKey,
      );
      return;
    }
    await _store.enqueue(
      ProgressTarget(bookId: bookId, page: page, completed: completed),
      scope: effectiveScope,
    );
    _authBlockedScopes.remove(effectiveScope);
    unawaited(flush(scope: effectiveScope));
  }

  /// 解除指定服务器（或全部）的鉴权停手标记（切换服务器或重登后调用）。
  void resetAuthBlock([String? scope]) {
    if (scope == null) {
      _authBlockedScopes.clear();
    } else {
      _authBlockedScopes.remove(scope);
    }
  }

  /// 提交指定分区（默认当前活动服务器分区）的待提交项。
  /// 已在跑时登记待冲洗分区并复用同一个 Future，避免上一轮收尾瞬间新入队的进度漏刷。
  Future<void> flush({String? scope}) {
    final targetScope = scope ?? _activeScope();
    _pendingFlushScopes.add(targetScope);
    final running = _inFlight;
    if (running != null) return running;
    final completer = Completer<void>();
    _inFlight = completer.future;
    unawaited(
      _drainFlushLoop().whenComplete(() {
        _inFlight = null;
        completer.complete();
      }),
    );
    return completer.future;
  }

  Future<void> _drainFlushLoop() async {
    while (_pendingFlushScopes.isNotEmpty) {
      final batch = List<String>.of(_pendingFlushScopes);
      _pendingFlushScopes.clear();
      for (final scope in batch) {
        await _flushScope(scope);
      }
    }
  }

  Future<void> _flushScope(String scope) async {
    if (scope == kLocalSourceKey || _authBlockedScopes.contains(scope)) return;
    for (final item in await _store.pending(scope: scope)) {
      try {
        await _upload(scope, item.target);
        await _store.ack(item.target.bookId, item.seq, scope: scope);
      } on AuthFailure {
        _authBlockedScopes.add(scope);
        return;
      } on NotFoundFailure {
        await _store.ack(item.target.bookId, item.seq, scope: scope);
      } on BadRequestFailure {
        await _store.ack(item.target.bookId, item.seq, scope: scope);
      } on ShelfFailure {
        return;
      }
    }
  }

  /// 把一批书的进度换成指定服务器分区"本地优先"的版本。
  Future<List<Book>> overlay(List<Book> books, {String? scope}) async {
    if (books.isEmpty) return books;
    final targetScope = scope ?? _activeScope();
    final records = await _store.records(
      books.map((Book b) => b.id),
      scope: targetScope,
    );
    var needsFlush = false;

    final merged = <Book>[];
    for (final book in books) {
      noteBook(book, scope: targetScope);
      final record = records[book.id];
      final decision = _decide(record, book.readProgress);

      switch (decision.action) {
        case SyncAction.pushLocal:
          needsFlush = true;
          merged.add(book.withProgress(record!.toReadProgress()));
        case SyncAction.adoptRemote:
          await _store.adoptRemote(
            book.id,
            decision.remote,
            scope: targetScope,
          );
          merged.add(book.withProgress(decision.remote));
        case SyncAction.inSync || SyncAction.staleRemote:
          merged.add(
            book.withProgress(record?.toReadProgress() ?? book.readProgress),
          );
      }
    }

    if (needsFlush) unawaited(flush(scope: targetScope));
    return merged;
  }

  /// 单本叠加（阅读器 resume 用）。
  Future<Book?> overlayOne(Book? book, {String? scope}) async {
    if (book == null) return null;
    return (await overlay(<Book>[book], scope: scope)).single;
  }

  /// 指定服务器分区中"尚未同步成功且仍在读"的本地书籍（按最近写入倒序）。
  Future<List<Book>> pendingInProgressBooks({
    Future<Book?> Function(String bookId)? loadBook,
    String? scope,
  }) async {
    final targetScope = scope ?? _activeScope();
    final pending = await _store.pending(scope: targetScope);
    if (pending.isEmpty) return const <Book>[];

    final known = _knownBooks[targetScope];
    final records = await _store.records(
      pending.map((PendingProgress p) => p.target.bookId),
      scope: targetScope,
    );
    final result = <Book>[];
    for (final item in pending.reversed) {
      final target = item.target;
      if (target.completed || target.page <= 0) continue;
      final base = known?[target.bookId] ?? await loadBook?.call(target.bookId);
      if (base == null) continue;
      final progress =
          records[target.bookId]?.toReadProgress() ??
          ReadProgress(
            page: target.page,
            completed: false,
            lastModified: DateTime.now().toUtc(),
          );
      result.add(base.withProgress(progress));
    }
    return result;
  }

  SyncDecision _decide(ProgressRecord? record, ReadProgress? remote) {
    final base = record?.serverLastModified == null
        ? null
        : ReadProgress(
            page: record!.page,
            completed: record.completed,
            lastModified: record.serverLastModified!,
          );
    return decideSync(
      base: base,
      remote: remote,
      hasPending: record?.isPending ?? false,
    );
  }
}
