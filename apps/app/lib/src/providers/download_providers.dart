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
class DownloadsController extends Notifier<Map<String, DownloadStatus>> {
  bool _disposed = false;

  /// 一次只跑一本：并发下载只会互相抢带宽，进度也更难解释。
  final List<Book> _queue = <Book>[];
  String? _active;

  @override
  Map<String, DownloadStatus> build() {
    ref.onDispose(() => _disposed = true);
    return const <String, DownloadStatus>{};
  }

  DownloadService get _service => ref.read(downloadServiceProvider);

  Future<void> start(Book book) async {
    if (state[book.id]?.isRunning ?? false) return;
    if (_queue.any((Book queued) => queued.id == book.id)) return;
    if (_active == book.id) return;

    _queue.add(book);
    if (state[book.id] == null) {
      _set(book.id, const DownloadStatus(queued: true));
    }
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
      try {
        await _service.download(
          book,
          onProgress: (DownloadProgress progress) {
            _set(book.id, DownloadStatus(progress: progress));
          },
        );
      } on ShelfFailure catch (failure) {
        _set(book.id, DownloadStatus(error: failure.message));
      } finally {
        _active = null;
        // 成功/取消/失败都要让"已下载"标记重新查一次。
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
    _clear(bookId);
    if (!_disposed) {
      ref.invalidate(downloadedProvider(bookId));
      ref.invalidate(downloadedBooksProvider);
    }
  }

  Future<void> delete(Book book) async {
    await _service.delete(book);
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
