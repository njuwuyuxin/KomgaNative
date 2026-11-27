import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/data/download/download_service.dart';
import 'package:yomu/src/data/download/downloaded_book_record.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/providers/downloads_controller.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_platform/yomu_platform.dart';

export 'package:yomu/src/data/download/downloaded_book_record.dart';
export 'package:yomu/src/providers/downloads_controller.dart';

/// 按源查询单本已下载记录的键。
typedef ScopedDownloadQuery = ({String? sourceKey, String bookId});

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

/// 远程离线下载的默认服务器分区键：优先跟随当前激活远程源，其次回退当前已连接会话。
final Provider<String> downloadScopeProvider = Provider<String>((Ref ref) {
  final active = ref.watch(activeSourceProvider);
  if (active.isCloud) return active.sourceKey;
  final session = ref.watch(sessionProvider);
  return session is SessionConnected ? session.server.address.baseUrl : '';
});

/// 默认下载服务：从当前远程源对应的 [SourceBundle] 获取（未连接远程源时返回空实现）。
final Provider<DownloadService> downloadServiceProvider =
    Provider<DownloadService>((Ref ref) {
      final scope = ref.watch(downloadScopeProvider);
      if (scope.isEmpty) return const NoopDownloadService();
      return ref
              .watch(sourceRegistryProvider)
              .remoteBundleOrNull(scope)
              ?.download ??
          const NoopDownloadService();
    });

/// 按非空 `sourceKey` 路由获取对应内容源的 [DownloadService]（P1-1 / P1-2）。
final downloadServiceForSourceProvider =
    Provider.family<DownloadService, String>((Ref ref, String sourceKey) {
      return ref
              .watch(sourceRegistryProvider)
              .bundleOrNull(sourceKey)
              ?.download ??
          const NoopDownloadService();
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
final downloadedBooksProvider = FutureProvider<List<DownloadedBookRecord>>((
  Ref ref,
) async {
  final scope = ref.watch(downloadScopeProvider);
  final db = ref.watch(httpCacheDatabaseProvider);
  final sub = db.downloadedBooksUpdates().listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  final rows = await db.downloads(scope: scope);
  return <DownloadedBookRecord>[
    for (final row in rows)
      DownloadedBookRecord(
        scope: row.scope,
        bookId: row.bookId,
        seriesId: row.seriesId,
        bookName: row.bookName,
        pageCount: row.pageCount,
        bytes: row.bytes,
        savedAt: row.savedAt,
      ),
  ];
});

/// 当前服务器待恢复的下载队列（ARC-07）。
final downloadQueueProvider = FutureProvider<List<DownloadQueueEntry>>((
  Ref ref,
) {
  final scope = ref.watch(downloadScopeProvider);
  return ref.watch(httpCacheDatabaseProvider).downloadQueue(scope: scope);
});

/// 下载管理页要显示书名：按显式 `(sourceKey, bookId)` 路由查书（失败返回 null，不打断列表）。
///
/// 必须按下载记录自身的远端 `scope` 查对应内容源，绝不跟随当前书架激活源（防止在"本机"
/// 分组下打开或重试已下载云端书时误路由到本机库并造成跨分区进度污染）。
final bookByIdProvider = FutureProvider.family<Book?, ScopedDownloadQuery>((
  Ref ref,
  ScopedDownloadQuery query,
) async {
  final rawScope = query.sourceKey;
  final scope = (rawScope != null && rawScope.isNotEmpty)
      ? rawScope
      : ref.watch(downloadScopeProvider);
  if (scope.isEmpty) return null;
  try {
    final fetched = await ref
        .watch(libraryRepositoryForSourceProvider(scope))
        .book(query.bookId);
    return fetched?.withSource(scope);
  } on ShelfFailure {
    return null;
  }
});

/// 某本书是否已整本下载（默认活动下载源；兼容既有调用与单测）。
final downloadedProvider = FutureProvider.family<DownloadedBook?, String>((
  Ref ref,
  String bookId,
) {
  return ref.watch(downloadServiceProvider).downloaded(bookId);
});

/// 按显式 `sourceKey` 查询某本书是否已整本下载（P1-2 跨源下载支持）。
final downloadedForSourceProvider =
    FutureProvider.family<DownloadedBook?, ScopedDownloadQuery>((
      Ref ref,
      ScopedDownloadQuery query,
    ) {
      final rawScope = query.sourceKey;
      final scope = (rawScope != null && rawScope.isNotEmpty)
          ? rawScope
          : ref.watch(downloadScopeProvider);
      if (scope.isEmpty) return Future<DownloadedBook?>.value(null);
      return ref
          .watch(downloadServiceForSourceProvider(scope))
          .downloaded(query.bookId);
    });

final downloadsProvider =
    NotifierProvider<DownloadsController, Map<String, DownloadStatus>>(
      DownloadsController.new,
    );
