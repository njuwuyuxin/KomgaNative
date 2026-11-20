import 'dart:async';

import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

/// 单服进度上传接口（单测便捷入口）。
typedef ProgressUpload = Future<void> Function(ProgressTarget target);

/// 带服务器分区校验的进度上传接口（ARC-07）。
typedef ScopedProgressUpload = Future<void> Function(
  String scope,
  ProgressTarget target,
);

/// 进度同步：本地按服务器分区先写，再仅对当前连接服务器尽力提交。
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
  final Set<String> _authBlockedScopes = <String>{};

  ProgressStore get store => _store;

  /// 用户显式改了阅读状态（标记已读/未读）后调用：本地那份 pending 已过期。
  Future<void> forceAdopt(String bookId, ReadProgress? remote) =>
      _store.forceAdopt(bookId, remote, scope: _activeScope());

  /// 记一页进度：先落入当前服务器分区，再尽力提交（不阻塞调用方）。
  Future<void> save(
    String bookId, {
    required int page,
    required bool completed,
  }) async {
    final scope = _activeScope();
    await _store.enqueue(
      ProgressTarget(bookId: bookId, page: page, completed: completed),
      scope: scope,
    );
    _authBlockedScopes.remove(scope);
    unawaited(flush());
  }

  /// 解除指定服务器（或全部）的鉴权停手标记（切换服务器或重登后调用）。
  void resetAuthBlock([String? scope]) {
    if (scope == null) {
      _authBlockedScopes.clear();
    } else {
      _authBlockedScopes.remove(scope);
    }
  }

  /// 提交当前活动服务器分区的待提交项。已在跑就直接复用同一个 Future（单飞）。
  Future<void> flush() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _flushLoop();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<void> _flushLoop() async {
    final scope = _activeScope();
    if (_authBlockedScopes.contains(scope)) return;
    for (final item in await _store.pending(scope: scope)) {
      // 若冲洗中途用户切换了服务器，立即停手，绝不把旧服条目发给新服。
      if (_activeScope() != scope) return;
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

  /// 把一批书的进度换成当前服务器分区"本地优先"的版本。
  Future<List<Book>> overlay(List<Book> books) async {
    if (books.isEmpty) return books;
    final scope = _activeScope();
    final records = await _store.records(
      books.map((Book b) => b.id),
      scope: scope,
    );
    var needsFlush = false;

    final merged = <Book>[];
    for (final book in books) {
      final record = records[book.id];
      final decision = _decide(record, book.readProgress);

      switch (decision.action) {
        case SyncAction.pushLocal:
          needsFlush = true;
          merged.add(book.withProgress(record!.toReadProgress()));
        case SyncAction.adoptRemote:
          await _store.adoptRemote(book.id, decision.remote, scope: scope);
          merged.add(book.withProgress(decision.remote));
        case SyncAction.inSync || SyncAction.staleRemote:
          merged.add(
            book.withProgress(record?.toReadProgress() ?? book.readProgress),
          );
      }
    }

    if (needsFlush) unawaited(flush());
    return merged;
  }

  /// 单本叠加（阅读器 resume 用）。
  Future<Book?> overlayOne(Book? book) async {
    if (book == null) return null;
    return (await overlay(<Book>[book])).single;
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
