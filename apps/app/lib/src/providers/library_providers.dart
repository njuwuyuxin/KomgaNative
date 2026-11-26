import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/collections_providers.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/paged_list_controller.dart';
import 'package:yomu/src/providers/shelf_controller.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu_domain/yomu_domain.dart';

export 'package:yomu/src/providers/collections_providers.dart';
export 'package:yomu/src/providers/paged_list_controller.dart';
export 'package:yomu/src/providers/search_providers.dart';
export 'package:yomu/src/providers/shelf_controller.dart';

/// 书架目录仓库：跟随当前激活内容源（本机或已选 Komga 服务器，ADR 0008）。
final Provider<LibraryRepository> libraryRepositoryProvider =
    Provider<LibraryRepository>((Ref ref) {
      return ref.watch(activeSourceBundleProvider).library;
    });

/// 已读/未读状态变更仓库（ARC-09 / ADR 0008）。
final Provider<ReadStatusRepository> readStatusRepositoryProvider =
    Provider<ReadStatusRepository>((Ref ref) {
      final lib = ref.watch(libraryRepositoryProvider);
      if (lib is ReadStatusRepository) return lib as ReadStatusRepository;
      return ref.watch(activeSourceBundleProvider).readStatus;
    });

/// 当前账号可见的库（用于筛选条）。
final FutureProvider<List<Library>> librariesProvider =
    FutureProvider<List<Library>>((Ref ref) {
      return ref.watch(libraryRepositoryProvider).libraries();
    });

/// 按源寻址单个系列的查询键。
typedef SeriesQuery = ({String? sourceKey, String seriesId});

/// 按源寻址封面图片的查询键（系列或书籍）。
typedef CoverQuery = ({String? sourceKey, String id});

/// 单张系列封面。失败返回 null，由占位图兜住。
final seriesCoverProvider = FutureProvider.family<Uint8List?, CoverQuery>((
  Ref ref,
  CoverQuery query,
) {
  return ref
      .watch(libraryRepositoryForSourceProvider(query.sourceKey))
      .seriesCover(query.id);
});

/// 单个系列（详情页头部用；系列被删时返回 null）。
final seriesDetailProvider = FutureProvider.family<Series?, SeriesQuery>((
  Ref ref,
  SeriesQuery query,
) {
  return ref
      .watch(libraryRepositoryForSourceProvider(query.sourceKey))
      .seriesById(query.seriesId);
});

/// 系列内书列表查询条件（SER-01 / ARC-12：增量分页每页固定 100 本）。
typedef SeriesBooksQuery = ({
  String? sourceKey,
  String seriesId,
  BooksSort? sort,
  SeriesReadStatus? readStatus,
});

const int kSeriesBooksPageSize = 100;

/// 系列内书列表增量分页控制器（ARC-12：`loadMore()` 只请求 `page = 1, 2...`）。
class SeriesBooksController extends PagedListController<Book> {
  SeriesBooksController(this.query);

  final SeriesBooksQuery query;

  @override
  int get pageSize => kSeriesBooksPageSize;

  @override
  Future<PageResult<Book>> fetchPage(int page, int size) => ref
      .watch(libraryRepositoryForSourceProvider(query.sourceKey))
      .books(
        query.seriesId,
        page: page,
        size: size,
        sort: query.sort,
        readStatus: query.readStatus,
      );
}

final seriesBooksProvider =
    AsyncNotifierProvider.family<
      SeriesBooksController,
      PageResult<Book>,
      SeriesBooksQuery
    >(SeriesBooksController.new);

/// 单本书的封面。
final bookCoverProvider = FutureProvider.family<Uint8List?, CoverQuery>((
  Ref ref,
  CoverQuery query,
) {
  return ref
      .watch(libraryRepositoryForSourceProvider(query.sourceKey))
      .bookCover(query.id);
});

/// 最近添加的系列（"正在读"首页的第二块，UI-P2-6）。
final recentSeriesProvider = FutureProvider<List<Series>>((Ref ref) async {
  final page = await ref
      .watch(libraryRepositoryProvider)
      .series(sort: SeriesSort.recentlyAdded, size: 20);
  return page.items;
});

/// 某个库里的系列（"正在读"首页按库分组的横向货架）。
final libraryShelfProvider = FutureProvider.family<List<Series>, String>((
  Ref ref,
  String libraryId,
) async {
  final page = await ref
      .watch(libraryRepositoryProvider)
      .series(libraryId: libraryId, size: 15);
  return page.items;
});

/// 阅读状态变更纪元（ARC-10）：每次标为已读/未读后自增，驱动已挂载的书架原地刷新。
class ReadStatusEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final NotifierProvider<ReadStatusEpoch, int> readStatusEpochProvider =
    NotifierProvider<ReadStatusEpoch, int>(ReadStatusEpoch.new);

/// 继续阅读：生产态跨源无感汇聚（本机 + 已连服务器），单测 override 仓库时走被测仓库。
final ondeckProvider = FutureProvider<PageResult<Book>>((Ref ref) {
  final primary = ref.watch(libraryRepositoryProvider);
  final activeBundle = ref.watch(activeSourceBundleProvider);
  if (!identical(primary, activeBundle.library)) {
    return primary.ondeck();
  }
  return ref.watch(crossSourceOndeckProvider.future);
});

/// 按书籍实体所属 `sourceKey` 路由封面（兼容单测 override `libraryRepositoryProvider`）。
final bookCoverForEntityProvider = FutureProvider.family<Uint8List?, Book>((
  Ref ref,
  Book book,
) {
  return ref
      .watch(libraryRepositoryForSourceProvider(book.sourceKey))
      .bookCover(book.id);
});

/// 本机书库发生导入、扫描、传书或元数据/分卷增删改后，统一失效相关缓存并原地刷新本机书架，
/// 确保已缓存的系列详情与分卷列表立即反映新卷而无需手动下拉刷新。
void invalidateLocalCatalogProviders(Ref ref, {bool includeCuration = false}) {
  ref.read(localLibraryRepositoryProvider).evictCoverCache();
  ref.invalidate(seriesCoverProvider);
  ref.invalidate(bookCoverProvider);
  ref.invalidate(seriesDetailProvider);
  ref.invalidate(seriesBooksProvider);
  ref.invalidate(crossSourceOndeckProvider);
  ref.invalidate(recentSeriesProvider);
  if (includeCuration) {
    ref.invalidate(collectionsProvider);
    ref.invalidate(readListsProvider);
  }
  if (!ref.read(activeSourceProvider).isCloud) {
    unawaited(ref.read(shelfProvider.notifier).refreshInPlace());
  }
}
