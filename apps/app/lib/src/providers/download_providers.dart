import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/downloads_controller.dart';
import 'package:yomu/src/providers/komga_session_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_platform/yomu_platform.dart';

export 'package:yomu/src/providers/downloads_controller.dart';

/// 当前生效的下载策略（DLD-01）：仅 Wi-Fi、读完自动删除、并发数。
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

/// 下载服务：已连接 Komga 时复用共享连接池，未连接服务器时返回空实现而不抛异常。
final Provider<DownloadService> downloadServiceProvider =
    Provider<DownloadService>((Ref ref) {
      final komga = ref.watch(komgaSessionProvider);
      if (komga == null) return const _NoopDownloadService();
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
        bookMeta: (String bookId) async {
          try {
            await komga.fetchBook(bookId);
          } on KomgaError {
            // 元信息预热失败不阻断页图下载。
          }
        },
        db: ref.watch(httpCacheDatabaseProvider),
        scope: komga.address.baseUrl,
      );
    });

/// 远程离线下载专属的服务器分区键（即使当前书架切到了本机源，仍展示已连接服务器的离线下载）。
final Provider<String> downloadScopeProvider = Provider<String>((Ref ref) {
  final session = ref.watch(sessionProvider);
  return session is SessionConnected ? session.server.address.baseUrl : '';
});

/// 当前服务器已下载书籍的合计占用（设置页，ARC-07 / ARC-10 Drift 表更新流驱动）。
final downloadsUsageProvider = FutureProvider<CacheUsage>((Ref ref) {
  final scope = ref.watch(downloadScopeProvider);
  final db = ref.watch(httpCacheDatabaseProvider);
  final sub = db.downloadedBooksUpdates().listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return db.downloadsUsage(scope: scope);
});

/// 当前服务器已下载书籍列表（下载管理页，UI-P3-13 / ARC-07 / ARC-10 Drift 表更新流驱动）。
final downloadedBooksProvider = FutureProvider<List<DownloadedBook>>((Ref ref) {
  final scope = ref.watch(downloadScopeProvider);
  final db = ref.watch(httpCacheDatabaseProvider);
  final sub = db.downloadedBooksUpdates().listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return db.downloads(scope: scope);
});

/// 当前服务器待恢复的下载队列（ARC-07）。
final downloadQueueProvider = FutureProvider<List<DownloadQueueEntry>>((
  Ref ref,
) {
  final scope = ref.watch(downloadScopeProvider);
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

final downloadsProvider =
    NotifierProvider<DownloadsController, Map<String, DownloadStatus>>(
      DownloadsController.new,
    );

class _NoopDownloadService implements DownloadService {
  const _NoopDownloadService();

  @override
  Future<DownloadedBook?> downloaded(String bookId) async => null;

  @override
  Future<bool> download(
    Book book, {
    required void Function(DownloadProgress progress) onProgress,
  }) async => false;

  @override
  void cancel(String bookId) {}

  @override
  Future<void> delete(Book book) async {}
}
