import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/download/download_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/session/session_controller.dart';

/// 下载服务：跟着会话走（换服务器/重新登录就重建）。
///
/// 页图请求走带缓存的会话，所以下载完的页就是离线可读的页——两件事共用一条链路，
/// 不需要"下载目录"这种东西。
final Provider<DownloadService> downloadServiceProvider =
    Provider<DownloadService>((Ref ref) {
      final session = ref.watch(sessionProvider);
      if (session is! SessionConnected) {
        throw StateError('未连接服务器时不应下载');
      }
      final komga = KomgaSession.withApiKey(
        address: session.server.address,
        apiKey: session.server.apiKey,
        trust: session.server.tls,
        cache: ref.watch(httpCacheProvider),
      );
      ref.onDispose(komga.close);
      return KomgaDownloadService(
        pages: (String bookId) async {
          try {
            return await komga.fetchBookPages(bookId);
          } on KomgaError catch (error) {
            throw shelfFailureOf(error);
          }
        },
        pageImage: (String bookId, int page) async {
          try {
            return await komga.fetchPageImage(bookId, page);
          } on KomgaError catch (error) {
            throw shelfFailureOf(error);
          }
        },
        db: ref.watch(httpCacheDatabaseProvider),
        scope: session.server.address.baseUrl,
      );
    });

/// 已下载书籍的合计占用（设置页）。
final downloadsUsageProvider = FutureProvider<CacheUsage>((Ref ref) {
  return ref.watch(httpCacheDatabaseProvider).downloadsUsage();
});

/// 已下载书籍列表（下载管理页，UI-P3-13）。
final downloadedBooksProvider = FutureProvider<List<DownloadedBook>>((Ref ref) {
  return ref.watch(httpCacheDatabaseProvider).downloads();
});

/// 磁盘上待恢复的下载队列（下载管理页用来显示"重启前还在排队"的书）。
final downloadQueueProvider = FutureProvider<List<DownloadQueueEntry>>((
  Ref ref,
) {
  return ref.watch(httpCacheDatabaseProvider).downloadQueue();
});

/// 下载管理页要显示书名：按 bookId 取一次（失败返回 null，不打断列表）。
final bookByIdProvider = FutureProvider.family<Book?, String>((
  Ref ref,
  String bookId,
) {
  return ref.watch(libraryRepositoryProvider).book(bookId);
});

/// 某本书是否已整本下载（返回记录，含页数与字节数）。
final downloadedProvider = FutureProvider.family<DownloadedBook?, String>((
  Ref ref,
  String bookId,
) {
  return ref.watch(downloadServiceProvider).downloaded(bookId);
});

/// 单本书的下载状态：进行中（带进度）或失败信息。
class DownloadStatus {
  const DownloadStatus({this.progress, this.error, this.queued = false});

  final DownloadProgress? progress;
  final String? error;

  /// 在队列里等前面那本下完（UI-P3-13）。
  final bool queued;

  bool get isRunning => progress != null;
}

/// 下载队列状态。
///
/// **下载本身在线程/服务层继续跑**，这里只维护"界面上要显示的进度"；
/// 离开系列页后 notifier 会被销毁，回调必须检查 `_disposed` 才能写状态。
///
/// 队列同时落盘（FIX-07）：杀进程后重启能看到"排队中"并自动接着下，
/// 而不是假装什么都没发生过。
class DownloadsController extends Notifier<Map<String, DownloadStatus>> {
  bool _disposed = false;

  /// 一次只跑一本：并发下载只会互相抢带宽，进度也更难解释。
  final List<Book> _queue = <Book>[];
  String? _active;

  /// 恢复是否已经做过：`build` 会在每次被订阅时跑一次，恢复只做一次。
  bool _restored = false;

  @override
  Map<String, DownloadStatus> build() {
    ref.onDispose(() => _disposed = true);
    // 队列从 [downloadQueueProvider] 读：读库失败会变成 `AsyncError` 而不是
    // 未捕获异常（直接 `unawaited` 一个裸 Future 时，缓存库打不开会把
    // 整棵 widget 树炸掉——黄金图测试里当场撞到）。
    ref.listen<AsyncValue<List<DownloadQueueEntry>>>(downloadQueueProvider, (
      AsyncValue<List<DownloadQueueEntry>>? _,
      AsyncValue<List<DownloadQueueEntry>> next,
    ) {
      final entries = next.value;
      if (entries == null || entries.isEmpty) return;
      // 延到微任务：build 还没返回时不能写 state。
      unawaited(Future<void>.microtask(() => _restore(entries)));
    }, fireImmediately: true);
    return const <String, DownloadStatus>{};
  }

  DownloadService get _service => ref.read(downloadServiceProvider);

  HttpCacheDatabase get _db => ref.read(httpCacheDatabaseProvider);

  /// 队列落盘：失败只影响"重启能否恢复"，绝不能打断下载本身。
  ///
  /// 缓存库可能打不开（平台通道缺失、磁盘满、库被锁），这些都不该让
  /// "点下载"变成无响应。
  void _persist(Future<void> work) {
    unawaited(work.catchError((Object _) {}));
  }

  /// 从磁盘恢复队列，然后接着下。
  ///
  /// 恢复要跳过两类条目：已经下载完的（上次刚好下完没来得及清）、
  /// 以及书已经不在服务器上的（下载时会 404 失败，这里先按"查得到"放过）。
  Future<void> _restore(List<DownloadQueueEntry> entries) async {
    if (_restored || _disposed) return;
    _restored = true;

    for (final entry in entries) {
      if (_disposed) return;
      // 用户可能在恢复落地前就点了下载：已经在跑/在排队的不要重复加。
      if (entry.bookId == _active ||
          _queue.any((Book queued) => queued.id == entry.bookId)) {
        continue;
      }
      var alreadyDownloaded = false;
      try {
        alreadyDownloaded = await _db.download(entry.bookId) != null;
      } on Object {
        // 查不了就按"没下完"处理：多下一次比永远不恢复强。
      }
      if (alreadyDownloaded) {
        // 上次已完成，只是队列行没删干净。
        _persist(_db.dequeueDownload(entry.bookId));
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
      // 用户可能已经手动开始过这一本：不要把它从"下载中"改回"排队中"。
      if (state[entry.bookId] == null) {
        _set(entry.bookId, const DownloadStatus(queued: true));
      }
    }
    if (_queue.isNotEmpty) await _pump();
  }

  Future<void> start(Book book) async {
    if (state[book.id]?.isRunning ?? false) return;
    if (_queue.any((Book queued) => queued.id == book.id)) return;
    if (_active == book.id) return;

    _queue.add(book);
    if (state[book.id] == null) {
      _set(book.id, const DownloadStatus(queued: true));
    }
    // 落盘不阻塞出队：界面先显示"排队中"，写库按提交顺序跟在后面。
    _persist(
      _db.enqueueDownload(
        bookId: book.id,
        seriesId: book.seriesId,
        name: book.name,
        number: book.number,
        pagesCount: book.pagesCount,
      ),
    );
    await _pump();
  }

  Future<void> _pump() async {
    if (_active != null) return;
    while (_queue.isNotEmpty) {
      final book = _queue.removeAt(0);
      _active = book.id;
      _set(
        book.id,
        const DownloadStatus(progress: DownloadProgress(done: 0, total: 0)),
      );
      _persist(
        _db.updateQueueEntry(
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
        _active = null;
        // 成功/取消/失败都要让"已下载"标记重新查一次，并且清掉队列行。
        _persist(_db.dequeueDownload(book.id));
        if (!_disposed) {
          ref.invalidate(downloadedProvider(book.id));
          ref.invalidate(downloadedBooksProvider);
          ref.invalidate(downloadsUsageProvider);
        }
      }
      _clear(book.id);
    }
  }

  void cancel(String bookId) {
    _queue.removeWhere((Book book) => book.id == bookId);
    _service.cancel(bookId);
    _persist(_db.dequeueDownload(bookId));
    _clear(bookId);
    if (!_disposed) {
      ref.invalidate(downloadedProvider(bookId));
      ref.invalidate(downloadedBooksProvider);
    }
  }

  /// 取消全部：清空排队、取消正在下的那本、清掉磁盘上的队列。
  ///
  /// 已经下完的书**不动**：用户的意图是"别再下了"，不是"删掉我的下载"。
  void cancelAll() {
    final pending = <String>{..._queue.map((Book book) => book.id)};
    final active = _active;
    if (active != null) pending.add(active);
    _queue.clear();
    for (final id in pending) {
      _service.cancel(id);
    }
    _persist(_db.clearDownloadQueue());
    if (_disposed) return;
    state = <String, DownloadStatus>{
      for (final entry in state.entries)
        if (!pending.contains(entry.key)) entry.key: entry.value,
    };
    ref.invalidate(downloadedBooksProvider);
  }

  Future<void> delete(Book book) async {
    await _service.delete(book);
    _persist(_db.dequeueDownload(book.id));
    _clear(book.id);
    if (_disposed) return;
    ref.invalidate(downloadedProvider(book.id));
    ref.invalidate(downloadedBooksProvider);
    ref.invalidate(cacheUsageProvider);
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

final downloadsProvider =
    NotifierProvider<DownloadsController, Map<String, DownloadStatus>>(
      DownloadsController.new,
    );
