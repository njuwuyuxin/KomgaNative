import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_queue_persistence.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/download_policy_gate.dart';
import 'package:yomu/src/providers/download_providers.dart';

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
  final Set<String> _restoredScopes = <String>{};
  bool _checkingWifi = false;

  String get _currentScope => ref.read(downloadScopeProvider);

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

  Future<bool> retryOne(
    String bookId, {
    Book? fallback,
    String? sourceKey,
  }) async {
    final cached = fallback ?? _knownBooks[bookId];
    final Book? book;
    if (cached != null) {
      book = cached;
    } else {
      final scope = (sourceKey != null && sourceKey.isNotEmpty)
          ? sourceKey
          : _scopeForId(bookId);
      if (scope.isEmpty) return false;
      final query = (sourceKey: scope, bookId: bookId);
      ref.invalidate(bookByIdProvider(query));
      book = await ref.read(bookByIdProvider(query).future);
    }
    if (book == null || _disposed) return false;
    _clear(bookId);
    await start(book);
    return true;
  }

  Future<int> retryFailed() async {
    var queued = 0;
    for (final entry in state.entries.toList()) {
      if (entry.value.hasError && await retryOne(entry.key)) queued++;
    }
    return queued;
  }

  @override
  Map<String, DownloadStatus> build() {
    _disposed = false;
    _restoredScopes.clear();
    _paused = false;
    _checkingWifi = false;
    _queue.clear();
    _knownBooks.clear();
    _running.clear();
    ref.onDispose(() => _disposed = true);
    // 不 watch downloadScopeProvider：切换分组（如服务器 A -> 本机）不得重建控制器，
    // 否则进行中任务状态丢失、队列停摆、并发上限失效；改为按需监听各分区持久化队列恢复。
    ref.listen<AsyncValue<List<DownloadQueueEntry>>>(downloadQueueProvider, (
      AsyncValue<List<DownloadQueueEntry>>? _,
      AsyncValue<List<DownloadQueueEntry>> next,
    ) {
      final entries = next.value;
      if (entries == null || entries.isEmpty) return;
      final scope = _currentScope;
      if (_restoredScopes.contains(scope)) return;
      _restoredScopes.add(scope);
      unawaited(Future<void>.microtask(() => _restore(entries, scope)));
    }, fireImmediately: true);
    return const <String, DownloadStatus>{};
  }

  DownloadService _serviceFor(String scope) =>
      ref.read(downloadServiceForSourceProvider(scope.isEmpty ? null : scope));

  String _scopeForBook(Book book) =>
      book.isCloud ? book.sourceKey : _currentScope;

  Book _tagBook(Book book) {
    if (book.isCloud) return book;
    final scope = _currentScope;
    return scope.isNotEmpty ? book.withSource(scope) : book;
  }

  String _scopeForId(String bookId) => _knownBooks[bookId] is Book
      ? _scopeForBook(_knownBooks[bookId]!)
      : _currentScope;

  void _invalidateDownloaded(String bookId, String scope) {
    final scoped = scope.isEmpty ? null : scope;
    ref
      ..invalidate(downloadedProvider(bookId))
      ..invalidate(
        downloadedForSourceProvider((sourceKey: scoped, bookId: bookId)),
      );
    if (scoped != null) {
      ref.invalidate(
        downloadedForSourceProvider((sourceKey: null, bookId: bookId)),
      );
    }
  }

  DownloadQueuePersistence get _queueStore =>
      DownloadQueuePersistence(ref.read(httpCacheDatabaseProvider));

  Future<void> _restore(
    List<DownloadQueueEntry> entries,
    String fallbackScope,
  ) async {
    if (_disposed) return;
    final books = await _queueStore.filterPendingEntries(
      entries,
      fallbackScope: fallbackScope,
      isAlreadyTracked: _isActiveOrQueued,
    );
    if (_disposed || books.isEmpty) return;
    for (final book in books) {
      _knownBooks[book.id] = book;
      _queue.add(book);
      if (state[book.id] == null) {
        _set(book.id, const DownloadStatus(queued: true));
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
    final tagged = _tagBook(book);
    final scope = _scopeForBook(tagged);
    _knownBooks[tagged.id] = tagged;
    _queue.add(tagged);
    if (state[tagged.id] == null) {
      _set(tagged.id, const DownloadStatus(queued: true));
    }
    _queueStore.enqueue(tagged, scope: scope);
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
    if (ref.read(downloadPolicyProvider).value?.wifiOnly ?? false) {
      if (_checkingWifi) return;
      _checkingWifi = true;
      final blocked = await isBlockedByWifiPolicy(ref);
      _checkingWifi = false;
      if (blocked) {
        if (!_disposed && !_paused) pauseAll();
        return;
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
    _queueStore.clear();
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
