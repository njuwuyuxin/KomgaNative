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

  /// 提交当前活动服务器分区的待提交项。已在跑就直接复用同一个 Future（严格单飞，防同步重入）。
  Future<void> flush() {
    final running = _inFlight;
    if (running != null) return running;
    final completer = Completer<void>();
    _inFlight = completer.future;
    unawaited(
      _flushLoop().whenComplete(() {
        _inFlight = null;
        completer.complete();
      }),
    );
    return completer.future;
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
      noteBook(book, scope: scope);
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

  /// 当前服务器分区中"尚未同步成功且仍在读"的本地书籍（按最近写入倒序）。
  ///
  /// 解决"服务端同步失败/离线时，刚打开或翻过的书没有进入服务端 IN_PROGRESS 列表"：
  /// 优先用内存已知元信息构造 [Book]，未知时再尝试 [loadBook]（命中 HTTP 缓存或在线补查）。
  Future<List<Book>> pendingInProgressBooks({
    Future<Book?> Function(String bookId)? loadBook,
  }) async {
    final scope = _activeScope();
    final pending = await _store.pending(scope: scope);
    if (pending.isEmpty) return const <Book>[];

    final known = _knownBooks[scope];
    final records = await _store.records(
      pending.map((PendingProgress p) => p.target.bookId),
      scope: scope,
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
