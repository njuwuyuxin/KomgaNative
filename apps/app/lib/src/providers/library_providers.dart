import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/read_status_repository.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/paged_list_controller.dart';
import 'package:yomu/src/providers/source_registry_provider.dart';
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

/// 单张系列封面。失败返回 null，由占位图兜住。
final seriesCoverProvider = FutureProvider.family<Uint8List?, String>((
  Ref ref,
  String seriesId,
) {
  return ref.watch(libraryRepositoryProvider).seriesCover(seriesId);
});

/// 单个系列（详情页头部用；系列被删时返回 null）。
final seriesDetailProvider = FutureProvider.family<Series?, String>((
  Ref ref,
  String seriesId,
) {
  return ref.watch(libraryRepositoryProvider).seriesById(seriesId);
});

/// 系列内书列表查询条件（SER-01 / ARC-12：增量分页每页固定 100 本）。
typedef SeriesBooksQuery = ({
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
      .watch(libraryRepositoryProvider)
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
final bookCoverProvider = FutureProvider.family<Uint8List?, String>((
  Ref ref,
  String bookId,
) {
  return ref.watch(libraryRepositoryProvider).bookCover(bookId);
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
  final primary = ref.watch(libraryRepositoryProvider);
  final activeBundle = ref.watch(activeSourceBundleProvider);
  if (!identical(primary, activeBundle.library)) {
    return primary.bookCover(book.id);
  }
  return ref
      .watch(sourceRegistryProvider)
      .bundleFor(book.sourceKey)
      .library
      .bookCover(book.id);
});
