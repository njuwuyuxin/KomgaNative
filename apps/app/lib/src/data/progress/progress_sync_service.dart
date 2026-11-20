import 'dart:async';

import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/progress/progress_store.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_sync_engine/komga_sync_engine.dart';

/// 进度上传接口（真实现就是 `ReaderRepository.uploadProgress`）。
typedef ProgressUpload = Future<void> Function(ProgressTarget target);

/// 进度同步：本地先写，再尽力提交；拿不到服务端数据时以本地为准。
///
/// 三条规则（对应 ADR 0002）：
/// 1. `save` 只负责**入队 + 落盘**，网络失败不影响阅读；
/// 2. `flush` 单飞（同一时刻只有一条队列在跑），失败保留 pending 等下次触发；
/// 3. 401/403 后本轮停手：Key 失效时反复重试只会刷服务端日志，等重新登录再试。
class ProgressSyncService {
  ProgressSyncService({required ProgressStore store, required this.upload})
    : _store = store;

  final ProgressStore _store;
  final ProgressUpload upload;

  Future<void>? _inFlight;
  bool _authBlocked = false;

  ProgressStore get store => _store;

  /// 用户显式改了阅读状态（标记已读/未读）后调用：本地那份 pending 已过期。
  Future<void> forceAdopt(String bookId, ReadProgress? remote) =>
      _store.forceAdopt(bookId, remote);

  /// 记一页进度：先落盘，再尽力提交（不阻塞调用方）。
  Future<void> save(
    String bookId, {
    required int page,
    required bool completed,
  }) async {
    await _store.enqueue(
      ProgressTarget(bookId: bookId, page: page, completed: completed),
    );
    _authBlocked = false;
    unawaited(flush());
  }

  /// 提交所有待提交项。已在跑就直接复用同一个 Future（单飞）。
  Future<void> flush() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _flushLoop();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<void> _flushLoop() async {
    if (_authBlocked) return;
    for (final item in await _store.pending()) {
      try {
        await upload(item.target);
        await _store.ack(item.target.bookId, item.seq);
      } on AuthFailure {
        // Key 失效：保留 pending，但别继续打服务端。
        _authBlocked = true;
        return;
      } on NotFoundFailure {
        // 404（书已删除）：不可恢复，出队并继续冲洗后续书籍，绝不队头阻塞。
        await _store.ack(item.target.bookId, item.seq);
      } on BadRequestFailure {
        // 400（参数越界等不可恢复错误）：出队并继续冲洗后续书籍，下次 GET 对账更新基准。
        await _store.ack(item.target.bookId, item.seq);
      } on ShelfFailure {
        // 网络/服务端/证书错误：保留，等下次触发（翻页、进前台、刷新书架）。
        return;
      }
    }
  }

  /// 把一批书的进度换成"本地优先"的版本。
  ///
  /// 对账规则在 `komga_sync_engine.decideSync` 里（只信服务端 lastModified）；
  /// 这里负责取数据、执行决定、并把结果叠加到 [Book] 上给 UI。
  Future<List<Book>> overlay(List<Book> books) async {
    if (books.isEmpty) return books;
    final records = await _store.records(books.map((Book b) => b.id));
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
          await _store.adoptRemote(book.id, decision.remote);
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
