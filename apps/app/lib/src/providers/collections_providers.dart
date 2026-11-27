import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/missing_source_repository.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 一次增量分页拉取的条数（收藏集 / 阅读列表 / 搜索）。
const int kListPageSize = 30;

/// 选择器拉全量时的分页大小与页数上限（Komga 1.30.1 忽略 `unpaged=true`）。
const int _kAllPageSize = 100;
const int _kAllMaxPages = 20;

/// 收藏集与阅读列表仓库（跟随当前激活内容源；源未就绪或已删时返回 [MissingSourceRepository]）。
final Provider<CollectionsRepository> collectionsRepositoryProvider =
    Provider<CollectionsRepository>((Ref ref) {
      final active = ref.watch(activeSourceProvider);
      return ref.watch(activeSourceBundleProvider)?.collections ??
          MissingSourceRepository(active.sourceKey);
    });

/// 收藏集增量分页控制器（ARC-12）。
class CollectionsListController extends PagedListController<Collection> {
  @override
  int get pageSize => kListPageSize;

  @override
  Future<PageResult<Collection>> fetchPage(int page, int size) => ref
      .watch(collectionsRepositoryProvider)
      .collections(page: page, size: size);
}

final collectionsProvider =
    AsyncNotifierProvider<CollectionsListController, PageResult<Collection>>(
      CollectionsListController.new,
    );

/// 按非空 `sourceKey` 寻址的全量收藏集（供跨源系列详情页的收藏选择器使用）。
final allCollectionsForSourceProvider =
    FutureProvider.family<List<Collection>, String>((
      Ref ref,
      String sourceKey,
    ) async {
      final repo = ref.watch(collectionsRepositoryForSourceProvider(sourceKey));
      return _fetchAllPages<Collection>(
        (int page) => repo.collections(page: page, size: _kAllPageSize),
      );
    });

/// 选择器用的全量收藏集（当前激活源，自动翻页拉全，不截断）。
final FutureProvider<List<Collection>> allCollectionsProvider =
    FutureProvider<List<Collection>>((Ref ref) {
      final activeKey = ref.watch(activeSourceProvider).sourceKey;
      return ref.watch(allCollectionsForSourceProvider(activeKey).future);
    });

/// 单个收藏集元信息（含当前 `seriesIds`）。
final collectionDetailProvider = FutureProvider.family<Collection?, String>(
  (Ref ref, String collectionId) =>
      ref.watch(collectionsRepositoryProvider).collectionById(collectionId),
);

/// 某系列所属的收藏集列表（系列详情页收藏图标高亮状态用，按 `sourceKey` 路由）。
final seriesCollectionsProvider =
    FutureProvider.family<List<Collection>, SeriesQuery>((
      Ref ref,
      SeriesQuery query,
    ) {
      final key = resolveEffectiveSourceKey(ref, query.sourceKey);
      return ref
          .watch(collectionsRepositoryForSourceProvider(key))
          .seriesCollections(query.seriesId);
    });

/// 阅读列表增量分页控制器（ARC-12）。
class ReadListsController extends PagedListController<ReadList> {
  @override
  int get pageSize => kListPageSize;

  @override
  Future<PageResult<ReadList>> fetchPage(int page, int size) => ref
      .watch(collectionsRepositoryProvider)
      .readLists(page: page, size: size);
}

final readListsProvider =
    AsyncNotifierProvider<ReadListsController, PageResult<ReadList>>(
      ReadListsController.new,
    );

/// 按非空 `sourceKey` 寻址的全量阅读列表（供跨源系列详情页的阅读列表选择器使用）。
final allReadListsForSourceProvider =
    FutureProvider.family<List<ReadList>, String>((
      Ref ref,
      String sourceKey,
    ) async {
      final repo = ref.watch(collectionsRepositoryForSourceProvider(sourceKey));
      return _fetchAllPages<ReadList>(
        (int page) => repo.readLists(page: page, size: _kAllPageSize),
      );
    });

/// 选择器用的全量阅读列表（当前激活源，自动翻页拉全，不截断）。
final FutureProvider<List<ReadList>> allReadListsProvider =
    FutureProvider<List<ReadList>>((Ref ref) {
      final activeKey = ref.watch(activeSourceProvider).sourceKey;
      return ref.watch(allReadListsForSourceProvider(activeKey).future);
    });

/// 单个阅读列表元信息（含 `summary` 与当前 `bookIds`）。
final readListDetailProvider = FutureProvider.family<ReadList?, String>(
  (Ref ref, String readListId) =>
      ref.watch(collectionsRepositoryProvider).readListById(readListId),
);

/// 收藏集内系列增量分页控制器（ARC-12）。
class CollectionSeriesController extends PagedListController<Series> {
  CollectionSeriesController(this.collectionId);

  final String collectionId;

  @override
  int get pageSize => kListPageSize;

  @override
  Future<PageResult<Series>> fetchPage(int page, int size) => ref
      .watch(collectionsRepositoryProvider)
      .collectionSeries(collectionId, page: page, size: size);
}

final collectionSeriesProvider =
    AsyncNotifierProvider.family<
      CollectionSeriesController,
      PageResult<Series>,
      String
    >(CollectionSeriesController.new);

/// 阅读列表内书籍增量分页控制器（ARC-12）。
class ReadListBooksController extends PagedListController<Book> {
  ReadListBooksController(this.readListId);

  final String readListId;

  @override
  int get pageSize => kListPageSize;

  @override
  Future<PageResult<Book>> fetchPage(int page, int size) => ref
      .watch(collectionsRepositoryProvider)
      .readListBooks(readListId, page: page, size: size);
}

final readListBooksProvider =
    AsyncNotifierProvider.family<
      ReadListBooksController,
      PageResult<Book>,
      String
    >(ReadListBooksController.new);

Future<List<T>> _fetchAllPages<T>(
  Future<PageResult<T>> Function(int page) fetch,
) async {
  final items = <T>[];
  for (var page = 0; page < _kAllMaxPages; page++) {
    final result = await fetch(page);
    items.addAll(result.items);
    if (!result.hasMore || result.items.isEmpty) break;
  }
  return items;
}
