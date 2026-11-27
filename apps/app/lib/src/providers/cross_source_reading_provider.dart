import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 跨源单本封面查询参数。
typedef ScopedBookRef = ({String sourceKey, String bookId});

/// 跨源系列封面查询参数。
typedef ScopedSeriesRef = ({String sourceKey, String seriesId});

/// 按实体自身携带的 `sourceKey` 路由获取单本书封面（供跨源正在读与阅读历史使用）。
final scopedBookCoverProvider =
    FutureProvider.family<Uint8List?, ScopedBookRef>((
      Ref ref,
      ScopedBookRef req,
    ) async {
      final bundle = ref
          .watch(sourceRegistryProvider)
          .bundleOrNull(req.sourceKey);
      if (bundle == null) return null;
      return bundle.library.bookCover(req.bookId);
    });

/// 按实体自身携带的 `sourceKey` 路由获取系列封面。
final scopedSeriesCoverProvider =
    FutureProvider.family<Uint8List?, ScopedSeriesRef>((
      Ref ref,
      ScopedSeriesRef req,
    ) async {
      final bundle = ref
          .watch(sourceRegistryProvider)
          .bundleOrNull(req.sourceKey);
      if (bundle == null) return null;
      return bundle.library.seriesCover(req.seriesId);
    });

/// 首页「正在读」跨源无感汇聚（ADR 0008 不变量 3 / P3 懒加载保真）：
/// - 始终拉取「本机」书库；
/// - 远程侧仅按需解析「当前激活远程源 + 当前已连接会话源」（不遍历全部历史保存服务器建池）；
/// - 在读书籍（`!isUnread && !isCompleted`）按 `lastModified` 倒序排在最前，跨源最新读的那本始终居首；
/// - 紧随其后展示下一卷未读（`Up Next`）；
/// - 故障隔离：单个远程源断网或鉴权失败时，静默保留其余源的在读书，仅在全部源无书且当前活动远程源失败时抛错。
final FutureProvider<PageResult<Book>>
crossSourceOndeckProvider = FutureProvider<PageResult<Book>>((Ref ref) async {
  const targetSize = 20;
  final registry = ref.watch(sourceRegistryProvider);
  final activeSource = ref.watch(activeSourceProvider);
  final connectedServerId = ref.watch(
    sessionProvider.select(
      (SessionState s) => s is SessionConnected ? s.server.id : null,
    ),
  );

  final localFuture = registry.localBundle.library.ondeck(size: targetSize);
  final remoteKeys = <String>{
    if (activeSource.isCloud) activeSource.sourceKey,
    if (connectedServerId != null && connectedServerId.isNotEmpty)
      connectedServerId,
  };
  final remoteBundles = <SourceBundle>[
    for (final key in remoteKeys)
      if (registry.remoteBundleOrNull(key) case final SourceBundle bundle)
        bundle,
  ];

  final remoteResults =
      await Future.wait<
        ({String sourceKey, List<Book>? items, ShelfFailure? failure})
      >(<
        Future<({String sourceKey, List<Book>? items, ShelfFailure? failure})>
      >[
        for (final bundle in remoteBundles)
          () async {
            try {
              final page = await bundle.library.ondeck(size: targetSize);
              return (
                sourceKey: bundle.source.sourceKey,
                items: page.items,
                failure: null,
              );
            } on ShelfFailure catch (failure) {
              return (
                sourceKey: bundle.source.sourceKey,
                items: null,
                failure: failure,
              );
            }
          }(),
      ]);

  final localPage = await localFuture;
  final remoteItems = <Book>[];
  ShelfFailure? activeRemoteFailure;
  ShelfFailure? firstRemoteFailure;

  for (final r in remoteResults) {
    if (r.items != null) {
      remoteItems.addAll(r.items!);
    } else if (r.failure != null) {
      firstRemoteFailure ??= r.failure;
      if (r.sourceKey == activeSource.sourceKey) {
        activeRemoteFailure = r.failure;
      }
    }
  }

  if (remoteItems.isEmpty) {
    final failure = activeRemoteFailure ?? firstRemoteFailure;
    if (failure != null && localPage.items.isEmpty && activeSource.isCloud) {
      throw failure;
    }
    return localPage;
  }

  final merged = mergeCrossSourceContinueReading(
    localPage.items,
    remoteItems,
    limit: targetSize,
  );
  return PageResult<Book>(
    items: merged,
    totalElements: merged.length,
    page: 0,
    size: targetSize,
  );
});

/// 将多源「继续阅读」列表合并：在读书按最后阅读时间倒序居前，待读下一卷保序追加。
List<Book> mergeCrossSourceContinueReading(
  List<Book> localBooks,
  List<Book> remoteBooks, {
  int limit = 20,
}) {
  final active = <Book>[];
  final upNext = <Book>[];
  final seenKeys = <String>{};

  for (final book in <Book>[...localBooks, ...remoteBooks]) {
    final key = '${book.sourceKey}|${book.id}';
    if (book.isCompleted || !seenKeys.add(key)) continue;
    if (!book.isUnread) {
      active.add(book);
    } else {
      upNext.add(book);
    }
  }

  active.sort((Book a, Book b) {
    final ta =
        a.readProgress?.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb =
        b.readProgress?.lastModified ?? DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  });

  final combined = <Book>[...active, ...upNext];
  return combined.length <= limit ? combined : combined.sublist(0, limit);
}
