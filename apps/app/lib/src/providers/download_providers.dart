import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/data/download/download_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/komga_session_provider.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/pinned_series_provider.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_platform/komga_platform.dart';

/// 当前生效的下载策略（DLD-01）：仅 Wi-Fi、读完自动删除、并发数。
///
/// 单独一个 provider 而不是塞进 `SettingsState`：那里面只有外观/语言，
/// 而下载策略的消费者是 `DownloadsController`（非 UI），用快照读更直接。
/// 设置页改完会 `ref.invalidate(downloadPolicyProvider)`。
typedef DownloadPolicy = ({
  bool wifiOnly,
  bool autoDeleteRead,
  int concurrency,
});

final FutureProvider<DownloadPolicy> downloadPolicyProvider =
    FutureProvider<DownloadPolicy>((Ref ref) async {
      final settings = await ref.watch(settingsStoreProvider).load();
      return (
        wifiOnly: settings.downloadWifiOnly,
        autoDeleteRead: settings.downloadAutoDeleteRead,
        concurrency: settings.downloadConcurrency.clamp(1, 3),
      );
    });

/// 网络探测（DLD-01）；测试里覆盖成固定值。
final Provider<NetworkProbe> networkProbeProvider = Provider<NetworkProbe>(
  (Ref ref) => const SystemNetworkProbe(),
);

/// 下载服务：复用共享 [komgaSessionProvider] 连接池（ARC-09）。
final Provider<DownloadService> downloadServiceProvider =
    Provider<DownloadService>((Ref ref) {
      final komga = requireKomgaSession(ref, reason: '未连接服务器时不应下载');
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
        scope: komga.address.baseUrl,
      );
    });

/// 当前服务器已下载书籍的合计占用（设置页，ARC-07）。
final downloadsUsageProvider = FutureProvider<CacheUsage>((Ref ref) {
  final scope = ref.watch(activeServerKeyProvider);
  return ref.watch(httpCacheDatabaseProvider).downloadsUsage(scope: scope);
});

/// 当前服务器已下载书籍列表（下载管理页，UI-P3-13 / ARC-07）。
final downloadedBooksProvider = FutureProvider<List<DownloadedBook>>((Ref ref) {
  final scope = ref.watch(activeServerKeyProvider);
  return ref.watch(httpCacheDatabaseProvider).downloads(scope: scope);
});

/// 当前服务器待恢复的下载队列（ARC-07）。
final downloadQueueProvider = FutureProvider<List<DownloadQueueEntry>>((
  Ref ref,
) {
  final scope = ref.watch(activeServerKeyProvider);
  return ref.watch(httpCacheDatabaseProvider).downloadQueue(scope: scope);
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

  /// 正在下载的（DLD-01 并发数 > 1 时会有多本）。
  final Set<String> _running = <String>{};

  /// 同时下载几本；uild() 里从设置读，缺省 1。
  int _concurrency = 1;

  /// 暂停（DLD-02）：正在下的那几本会自然结束，但不再从队列取新的。
  bool _paused = false;

  bool get paused => _paused;

  /// 暂停：队列保留，不再启动新的。
  void pauseAll() {
    if (_paused) return;
    _paused = true;
    // 触发一次重建，让按钮从"暂停"变成"继续"。
    state = <String, DownloadStatus>{...state};
  }

  /// 继续：把暂停期间攒下的队列放出来。
  void resumeAll() {
    if (!_paused) return;
    _paused = false;
    unawaited(_pump());
    state = <String, DownloadStatus>{...state};
  }

  /// 重试失败项（DLD-02）：只针对错误态，不碰已下载/正在跑的。
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

  /// 恢复是否已经做过：`build` 会在每次被订阅或切服务器时跑一次。
  bool _restored = false;
  String _scope = '';

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
      if (_running.contains(entry.bookId) ||
          _queue.any((Book queued) => queued.id == entry.bookId)) {
        continue;
      }
      var alreadyDownloaded = false;
      try {
        alreadyDownloaded =
            await _db.download(entry.bookId, scope: _scope) != null;
      } on Object {
        // 查不了就按"没下完"处理：多下一次比永远不恢复强。
      }
      if (alreadyDownloaded) {
        // 上次已完成，只是队列行没删干净。
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
      // 用户可能已经手动开始过这一本：不要把它从"下载中"改回"排队中"。
      if (state[entry.bookId] == null) {
        _set(entry.bookId, const DownloadStatus(queued: true));
      }
    }
    if (_queue.isNotEmpty) await _pump();
  }

  /// 入队前把策略读进来（DLD-01）。
  ///
  /// 为什么不只靠 `build()` 里的 `ref.listen`：应用刚启动时设置还没读完，
  /// 用户立刻点下载就会按默认并发数跑。这里在每次入队前补一次，代价是一次
  /// 内存里的快照读取。
  /// 读一次策略（同步；读不到就保持当前值）。
  ///
  /// 为什么不用 `await .future`：那会让"点下载"卡在一次设置读取上，
  /// 而设置读不出来（平台通道缺失、存档损坏）时下载仍应可用。
  void _readPolicy() {
    final policy = ref.read(downloadPolicyProvider).value;
    if (policy != null) _concurrency = policy.concurrency;
  }

  Future<void> start(Book book) async {
    _readPolicy();
    if (state[book.id]?.isRunning ?? false) return;
    if (_queue.any((Book queued) => queued.id == book.id)) return;
    if (_running.contains(book.id)) return;

    _queue.add(book);
    if (state[book.id] == null) {
      _set(book.id, const DownloadStatus(queued: true));
    }
    // 落盘不阻塞出队：界面先显示"排队中"，写库按提交顺序跟在后面。
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
    await _pump();
  }

  /// 批量入队（SER-03）：跳过已经下好的、跳过已在队列/正在下的，返回实际入队数量。
  ///
  /// 为什么要在这里判重而不是交给 [start]：批量时每本都走一遍 `start` 会反复
  /// `_pump`，而且"跳过了几本"这个数字要能回给用户看。
  Future<({int queued, int skipped})> startMany(List<Book> books) async {
    _readPolicy();
    var queued = 0;
    var skipped = 0;
    for (final book in books) {
      final already =
          await _service.downloaded(book.id) != null ||
          _queue.any((Book q) => q.id == book.id) ||
          _running.contains(book.id) ||
          state[book.id]?.isRunning == true;
      if (already) {
        skipped++;
        continue;
      }
      _queue.add(book);
      queued++;
      _set(book.id, const DownloadStatus(queued: true));
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
    if (queued > 0) await _pump();
    return (queued: queued, skipped: skipped);
  }

  /// 取消指定的一批（SER-03 的"取消"按钮：只撤掉这次入队的）。
  void cancelMany(Iterable<String> bookIds) {
    for (final id in bookIds.toList()) {
      cancel(id);
    }
  }

  Future<void> _pump() async {
    if (_paused) return;
    // 并发：最多 _concurrency 本同时下（DLD-01）。每本跑在自己的 Future 里，
    // 下完再由 _runOne 回过头来补位。
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
        ref.invalidate(downloadedBooksProvider);
        ref.invalidate(downloadsUsageProvider);
      }
    }
    if (_disposed) return;
    // 只有成功/取消才清掉状态：**失败要留着**，否则"重试失败项"没有对象可重试，
    // 用户也看不到哪一本没下下来（这里之前是个 bug：finally 之后无条件 _clear）。
    final error = state[book.id]?.error;
    if (error == null) _clear(book.id);
    // 空出一个并发位，让排队的顶上。
    unawaited(_pump());
  }

  void cancel(String bookId) {
    _queue.removeWhere((Book book) => book.id == bookId);
    _service.cancel(bookId);
    _persist(_db.dequeueDownload(bookId, scope: _scope));
    _clear(bookId);
    if (!_disposed) {
      ref.invalidate(downloadedProvider(bookId));
      ref.invalidate(downloadedBooksProvider);
    }
  }

  /// 取消全部：清空当前服务器的排队与正在下的那本。
  void cancelAll() {
    final pending = <String>{..._queue.map((Book book) => book.id)};
    pending.addAll(_running);
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
    ref.invalidate(downloadedBooksProvider);
  }

  Future<void> delete(Book book) async {
    await _service.delete(book);
    _persist(_db.dequeueDownload(book.id, scope: _scope));
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
