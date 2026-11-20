import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/collections_repository.dart';
import 'package:komga_native/src/providers/komga_session_provider.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';

/// 一次增量分页拉取的条数（收藏集 / 阅读列表 / 搜索）。
const int kListPageSize = 30;

/// 收藏集与阅读列表仓库（ARC-09）。
final Provider<CollectionsRepository> collectionsRepositoryProvider =
    Provider<CollectionsRepository>((Ref ref) {
      final lib = ref.watch(libraryRepositoryProvider);
      if (lib is CollectionsRepository) return lib as CollectionsRepository;
      final komga = requireKomgaSession(ref, reason: '未连接服务器时不应读取收藏集');
      return KomgaCollectionsRepository(komga, ref.watch(progressSyncProvider));
    });

/// 收藏集增量分页控制器（ARC-12）。
class CollectionsListController extends PagedListController<KomgaCollection> {
  @override
  int get pageSize => kListPageSize;

  @override
  Future<PageResult<KomgaCollection>> fetchPage(int page, int size) => ref
      .watch(collectionsRepositoryProvider)
      .collections(page: page, size: size);
}

final collectionsProvider =
    AsyncNotifierProvider<
      CollectionsListController,
      PageResult<KomgaCollection>
    >(CollectionsListController.new);

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
