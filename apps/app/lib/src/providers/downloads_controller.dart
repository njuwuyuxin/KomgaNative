import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/download/download_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_native/src/providers/pinned_series_provider.dart';

/// 单本书的下载状态：进行中（带进度）或失败信息。
class DownloadStatus {
  const DownloadStatus({this.progress, this.error, this.queued = false});

  final DownloadProgress? progress;
  final String? error;
  final bool queued;

  bool get isRunning => progress != null;
}

/// 下载队列状态机（FIX-07 / DLD-01 / DLD-02 / ARC-07 / ARC-12）。
class DownloadsController extends Notifier<Map<String, DownloadStatus>> {
  bool _disposed = false;
  final List<Book> _queue = <Book>[];
  final Set<String> _running = <String>{};
  int _concurrency = 1;
  bool _paused = false;
  bool _restored = false;
  String _scope = '';

  bool get paused => _paused;

  void pauseAll() {
    if (_paused) return;
    _paused = true;
    state = <String, DownloadStatus>{...state};
  }

  void resumeAll() {
    if (!_paused) return;
    _paused = false;
    unawaited(_pump());
    state = <String, DownloadStatus>{...state};
  }

  Future<int> retryFailed() async {
    final failed = <String>[
      for (final entry in state.entries)
        if (entry.value.error != null) entry.key,
    ];
    if (failed.isEmpty) return 0;
    var queued = 0;
    for (final id in failed) {
      final book = await ref.read(bookByIdProvider(id).future);
      if (book == null) continue;
      _clear(id);
      await start(book);
      queued++;
    }
    return queued;
  }

  @override
  Map<String, DownloadStatus> build() {
    _disposed = false;
    _restored = false;
    _paused = false;
    _queue.clear();
    _running.clear();
    _scope = ref.watch(activeServerKeyProvider);
    ref.onDispose(() => _disposed = true);
    ref.listen<AsyncValue<List<DownloadQueueEntry>>>(downloadQueueProvider, (
      AsyncValue<List<DownloadQueueEntry>>? _,
      AsyncValue<List<DownloadQueueEntry>> next,
    ) {
      final entries = next.value;
      if (entries == null || entries.isEmpty) return;
      unawaited(Future<void>.microtask(() => _restore(entries)));
    }, fireImmediately: true);
    return const <String, DownloadStatus>{};
  }

  DownloadService get _service => ref.read(downloadServiceProvider);
  HttpCacheDatabase get _db => ref.read(httpCacheDatabaseProvider);

  void _persist(Future<void> work) {
    unawaited(work.catchError((Object _) {}));
  }

  Future<void> _restore(List<DownloadQueueEntry> entries) async {
    if (_restored || _disposed) return;
    _restored = true;

    for (final entry in entries) {
      if (_disposed) return;
      if (_running.contains(entry.bookId) ||
          _queue.any((Book queued) => queued.id == entry.bookId)) {
        continue;
      }
      var alreadyDownloaded = false;
      try {
        alreadyDownloaded =
            await _db.download(entry.bookId, scope: _scope) != null;
      } on Object {
        // 查不了按未下完恢复。
      }
      if (alreadyDownloaded) {
        _persist(_db.dequeueDownload(entry.bookId, scope: _scope));
        continue;
      }
      _queue.add(
        Book(
          id: entry.bookId,
          seriesId: entry.seriesId,
          name: entry.name,
          number: entry.number,
          pagesCount: entry.pagesCount,
        ),
      );
      if (state[entry.bookId] == null) {
        _set(entry.bookId, const DownloadStatus(queued: true));
      }
    }
    if (_queue.isNotEmpty) await _pump();
  }

  void _readPolicy() {
    final policy = ref.read(downloadPolicyProvider).value;
    if (policy != null) _concurrency = policy.concurrency;
  }

  Future<void> start(Book book) async {
    _readPolicy();
    if (_isActiveOrQueued(book.id)) return;
    _enqueueAndPersist(book);
    await _pump();
  }

  Future<({int queued, int skipped})> startMany(List<Book> books) async {
    _readPolicy();
    var queued = 0;
    var skipped = 0;
    for (final book in books) {
      final already =
          await _service.downloaded(book.id) != null ||
          _isActiveOrQueued(book.id);
      if (already) {
        skipped++;
        continue;
      }
      queued++;
      _enqueueAndPersist(book);
    }
    if (queued > 0) await _pump();
    return (queued: queued, skipped: skipped);
  }

  bool _isActiveOrQueued(String bookId) =>
      (state[bookId]?.isRunning ?? false) ||
      _running.contains(bookId) ||
      _queue.any((Book q) => q.id == bookId);

  void _enqueueAndPersist(Book book) {
    _queue.add(book);
    if (state[book.id] == null) {
      _set(book.id, const DownloadStatus(queued: true));
    }
    _persist(
      _db.enqueueDownload(
        scope: _scope,
        bookId: book.id,
        seriesId: book.seriesId,
        name: book.name,
        number: book.number,
        pagesCount: book.pagesCount,
      ),
    );
  }

  void cancelMany(Iterable<String> bookIds) {
    for (final id in bookIds.toList()) {
      cancel(id);
    }
  }

  Future<void> _pump() async {
    if (_paused) return;
    while (_queue.isNotEmpty && _running.length < _concurrency) {
      final book = _queue.removeAt(0);
      _running.add(book.id);
      unawaited(_runOne(book));
    }
  }

  Future<void> _runOne(Book book) async {
    final scope = _scope;
    _set(
      book.id,
      const DownloadStatus(progress: DownloadProgress(done: 0, total: 0)),
    );
    _persist(
      _db.updateQueueEntry(
        scope: scope,
        bookId: book.id,
        state: 'active',
        done: 0,
        total: 0,
      ),
    );
    try {
      await _service.download(
        book,
        onProgress: (DownloadProgress progress) {
          _set(book.id, DownloadStatus(progress: progress));
          _persist(
            _db.updateQueueEntry(
              scope: scope,
              bookId: book.id,
              state: 'active',
              done: progress.done,
              total: progress.total,
            ),
          );
        },
      );
    } on ShelfFailure catch (failure) {
      _set(book.id, DownloadStatus(error: failure.message));
    } finally {
      _running.remove(book.id);
      if (!_disposed) {
        _persist(_db.dequeueDownload(book.id, scope: scope));
        ref.invalidate(downloadedProvider(book.id));
      }
    }
    if (_disposed) return;
    if (state[book.id]?.error == null) _clear(book.id);
    unawaited(_pump());
  }

  void cancel(String bookId) {
    _queue.removeWhere((Book book) => book.id == bookId);
    _service.cancel(bookId);
    _persist(_db.dequeueDownload(bookId, scope: _scope));
    _clear(bookId);
    if (!_disposed) {
      ref.invalidate(downloadedProvider(bookId));
    }
  }

  void cancelAll() {
    final pending = <String>{..._queue.map((Book book) => book.id)}
      ..addAll(_running);
    _queue.clear();
    for (final id in pending) {
      _service.cancel(id);
    }
    _persist(_db.clearDownloadQueue(scope: _scope));
    if (_disposed) return;
    state = <String, DownloadStatus>{
      for (final entry in state.entries)
        if (!pending.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<void> delete(Book book) async {
    await _service.delete(book);
    _persist(_db.dequeueDownload(book.id, scope: _scope));
    _clear(book.id);
    if (!_disposed) ref.invalidate(downloadedProvider(book.id));
  }

  void dismiss(String bookId) => _clear(bookId);

  void _set(String bookId, DownloadStatus status) {
    if (_disposed) return;
    state = <String, DownloadStatus>{...state, bookId: status};
  }

  void _clear(String bookId) {
    if (_disposed) return;
    state = <String, DownloadStatus>{...state}..remove(bookId);
  }
}
