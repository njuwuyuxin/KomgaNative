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
    ) {
      final bundle = ref.watch(sourceRegistryProvider).bundleFor(req.sourceKey);
      return bundle.library.bookCover(req.bookId);
    });

/// 按实体自身携带的 `sourceKey` 路由获取系列封面。
final scopedSeriesCoverProvider =
    FutureProvider.family<Uint8List?, ScopedSeriesRef>((
      Ref ref,
      ScopedSeriesRef req,
    ) {
      final bundle = ref.watch(sourceRegistryProvider).bundleFor(req.sourceKey);
      return bundle.library.seriesCover(req.seriesId);
    });

/// 首页「正在读」跨源无感汇聚（ADR 0008 不变量 3）：
/// - 同时拉取「本机」与当前已连接 Komga 服务器的 `ondeck`；
/// - 在读书籍（`!isUnread && !isCompleted`）按 `lastModified` 倒序排在最前，跨源最新读的那本始终居首；
/// - 紧随其后展示下一卷未读（`Up Next`）；
/// - 故障隔离：远程服务器断网失败时，只要本机书库正常可读（或当前处于本机分组），静默保留本机在读书而不让首页报错。
final FutureProvider<PageResult<Book>> crossSourceOndeckProvider =
    FutureProvider<PageResult<Book>>((Ref ref) async {
      const targetSize = 20;
      final registry = ref.watch(sourceRegistryProvider);
      final session = ref.watch(sessionProvider);
      final activeSource = ref.watch(activeSourceProvider);

      final localFuture = registry.localBundle.library.ondeck(size: targetSize);

      PageResult<Book>? remotePage;
      ShelfFailure? remoteFailure;
      if (session is SessionConnected) {
        final remoteBundle = registry.remoteBundleOrNull(session.server.id);
        if (remoteBundle != null) {
          try {
            remotePage = await remoteBundle.library.ondeck(size: targetSize);
          } on ShelfFailure catch (failure) {
            remoteFailure = failure;
          }
        }
      }

      final localPage = await localFuture;
      if (remotePage == null) {
        if (remoteFailure != null &&
            localPage.items.isEmpty &&
            activeSource.isCloud) {
          throw remoteFailure;
        }
        return localPage;
      }
      if (localPage.items.isEmpty) {
        return remotePage;
      }

      final merged = mergeCrossSourceContinueReading(
        localPage.items,
        remotePage.items,
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
