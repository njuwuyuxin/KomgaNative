import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_queue_persistence.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 单本书的下载状态：进行中（带进度）、排队中或失败种类（按 Locale 渲染）。
class DownloadStatus {
  const DownloadStatus({this.progress, this.errorKind, this.queued = false});

  final DownloadProgress? progress;
  final ShelfFailureKind? errorKind;
  final bool queued;

  bool get isRunning => progress != null;
  bool get hasError => errorKind != null;
}

/// 下载队列状态机（FIX-07 / DLD-01 / DLD-02 / ARC-07 / ARC-12）。
class DownloadsController extends Notifier<Map<String, DownloadStatus>> {
  bool _disposed = false;
  final List<Book> _queue = <Book>[];
  final Map<String, Book> _knownBooks = <String, Book>{};
  final Set<String> _running = <String>{};
  int _concurrency = 1;
  bool _paused = false;
  bool _restored = false;
  bool _checkingWifi = false;
  String _scope = '';

  bool get paused => _paused;

  Book? knownBook(String bookId) => _knownBooks[bookId];

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

  Future<bool> retryOne(String bookId, {Book? fallback}) async {
    final book = await _resolveBook(bookId, fallback: fallback);
    if (book == null || _disposed) return false;
    _clear(bookId);
    await start(book);
    return true;
  }

  Future<int> retryFailed() async {
    final failed = <String>[
      for (final entry in state.entries)
        if (entry.value.hasError) entry.key,
    ];
    if (failed.isEmpty) return 0;
    var queued = 0;
    for (final id in failed) {
      if (await retryOne(id)) queued++;
    }
    return queued;
  }

  Future<Book?> _resolveBook(String bookId, {Book? fallback}) async {
    final cached = fallback ?? _knownBooks[bookId];
    if (cached != null) return cached;
    try {
      ref.invalidate(bookByIdProvider(bookId));
      return await ref.read(bookByIdProvider(bookId).future);
    } on Object {
      return null;
    }
  }

  @override
  Map<String, DownloadStatus> build() {
    _disposed = false;
    _restored = false;
    _paused = false;
    _checkingWifi = false;
    _queue.clear();
    _knownBooks.clear();
    _running.clear();
    _scope = ref.watch(downloadScopeProvider);
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

  DownloadService _serviceFor(String scope) =>
      ref.read(downloadServiceForSourceProvider(scope.isEmpty ? null : scope));

  String _scopeForBook(Book book) => book.isCloud ? book.sourceKey : _scope;

  String _scopeForId(String bookId) {
    final known = _knownBooks[bookId];
    return known != null ? _scopeForBook(known) : _scope;
  }

  void _invalidateDownloaded(String bookId, String scope) {
    ref.invalidate(downloadedProvider(bookId));
    ref.invalidate(
      downloadedForSourceProvider((
        sourceKey: scope.isEmpty ? null : scope,
        bookId: bookId,
      )),
    );
    if (scope.isNotEmpty) {
      ref.invalidate(
        downloadedForSourceProvider((sourceKey: null, bookId: bookId)),
      );
    }
  }

  HttpCacheDatabase get _db => ref.read(httpCacheDatabaseProvider);
  DownloadQueuePersistence get _queueStore => DownloadQueuePersistence(_db);

  Future<void> _restore(List<DownloadQueueEntry> entries) async {
    if (_restored || _disposed) return;
    _restored = true;
    for (final entry in entries) {
      if (_disposed) return;
      if (_running.contains(entry.bookId) ||
          _queue.any((Book q) => q.id == entry.bookId)) {
        continue;
      }
      if (await _queueStore.isDownloaded(entry.bookId, scope: _scope)) {
        _queueStore.dequeue(entry.bookId, scope: _scope);
        continue;
      }
      final book = Book(
        id: entry.bookId,
        seriesId: entry.seriesId,
        name: entry.name,
        number: entry.number,
        pagesCount: entry.pagesCount,
      );
      _knownBooks[book.id] = book;
      _queue.add(book);
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
      final scope = _scopeForBook(book);
      final already =
          await _serviceFor(scope).downloaded(book.id) != null ||
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
    final scope = _scopeForBook(book);
    _knownBooks[book.id] = book;
    _queue.add(book);
    if (state[book.id] == null) {
      _set(book.id, const DownloadStatus(queued: true));
    }
    _queueStore.enqueue(book, scope: scope);
  }

  void cancelMany(Iterable<String> bookIds) {
    for (final id in bookIds.toList()) {
      cancel(id);
    }
  }

  Future<void> _pump() async {
    if (_paused ||
        _disposed ||
        _queue.isEmpty ||
        _running.length >= _concurrency) {
      return;
    }
    final policy = ref.read(downloadPolicyProvider).value;
    if (policy?.wifiOnly ?? false) {
      if (_checkingWifi) return;
      _checkingWifi = true;
      try {
        final kind = await ref.read(networkProbeProvider).current();
        if (kind == NetworkKind.cellular) {
          if (!_disposed && !_paused) pauseAll();
          return;
        }
      } on Object catch (error) {
        // 探测失败按 unknown 放行。
        debugPrint('DownloadsController: network probe failed: $error');
      } finally {
        _checkingWifi = false;
      }
      if (_paused || _disposed) return;
    }
    while (_queue.isNotEmpty && _running.length < _concurrency) {
      final book = _queue.removeAt(0);
      _running.add(book.id);
      unawaited(_runOne(book));
    }
  }

  Future<void> _runOne(Book book) async {
    final scope = _scopeForBook(book);
    _set(
      book.id,
      const DownloadStatus(progress: DownloadProgress(done: 0, total: 0)),
    );
    _queueStore.markActive(scope, book.id, 0, 0);
    try {
      await _serviceFor(scope).download(
        book,
        onProgress: (DownloadProgress progress) {
          _set(book.id, DownloadStatus(progress: progress));
          _queueStore.markActive(scope, book.id, progress.done, progress.total);
        },
      );
    } on ShelfFailure catch (failure) {
      _set(book.id, DownloadStatus(errorKind: failure.kind));
    } finally {
      _running.remove(book.id);
      if (!_disposed) {
        _queueStore.dequeue(book.id, scope: scope);
        _invalidateDownloaded(book.id, scope);
      }
    }
    if (_disposed) return;
    if (!(state[book.id]?.hasError ?? false)) _clear(book.id);
    unawaited(_pump());
  }

  void cancel(String bookId) {
    final scope = _scopeForId(bookId);
    _queue.removeWhere((Book book) => book.id == bookId);
    _serviceFor(scope).cancel(bookId);
    _queueStore.dequeue(bookId, scope: scope);
    _clear(bookId);
    if (!_disposed) _invalidateDownloaded(bookId, scope);
  }

  void cancelAll() {
    final pending = <String>{..._queue.map((Book b) => b.id), ..._running};
    _queue.clear();
    for (final id in pending) {
      _serviceFor(_scopeForId(id)).cancel(id);
    }
    _queueStore.clear(scope: _scope);
    if (_disposed) return;
    state = <String, DownloadStatus>{
      for (final entry in state.entries)
        if (!pending.contains(entry.key)) entry.key: entry.value,
    };
  }

  Future<void> delete(Book book) async {
    final scope = _scopeForBook(book);
    await _serviceFor(scope).delete(book);
    _queueStore.dequeue(book.id, scope: scope);
    _clear(book.id);
    if (!_disposed) _invalidateDownloaded(book.id, scope);
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
