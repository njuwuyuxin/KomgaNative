import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/library_repository.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/session/session_controller.dart';

/// 书架仓库：由当前会话构造，会话变了就重建（并关掉旧的 dio 连接）。
final Provider<LibraryRepository> libraryRepositoryProvider =
    Provider<LibraryRepository>((Ref ref) {
      final session = ref.watch(sessionProvider);
      if (session is! SessionConnected) {
        // 只有已连接才会路由到书架；走到这里说明代码接错了，直接暴露。
        throw StateError('未连接服务器时不应读取书架');
      }
      final komga = KomgaSession.withApiKey(
        address: session.server.address,
        apiKey: session.server.apiKey,
        trust: session.server.tls,
        // 书架/封面/系列/书列表都走这个会话：GET 成功落盘，断网回退。
        cache: ref.watch(httpCacheProvider),
      );
      ref.onDispose(komga.close);
      return KomgaLibraryRepository(komga, ref.watch(progressSyncProvider));
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

/// 系列下的书（UI-P2-4：支持"加载更多"）。
///
/// 参数里带 `size` 而不是在 provider 内部翻页：翻页只是"要更多本"，服务端本来就
/// 支持一次给一页；把 `size` 放进 family key，请求"前 150 本"就是一次新查询，
/// 不需要在客户端拼列表，也不会出现两份不一致的书列表。
///
/// 默认仍取 100 本（绝大多数系列够用）；超过时详情页出现"加载更多"。
typedef SeriesBooksQuery = ({String seriesId, int size});

/// 一次"加载更多"多要多少本。
const int kSeriesBooksPageSize = 50;

final seriesBooksProvider =
    FutureProvider.family<PageResult<Book>, SeriesBooksQuery>((
      Ref ref,
      SeriesBooksQuery query,
    ) {
      return ref
          .watch(libraryRepositoryProvider)
          .books(query.seriesId, size: query.size);
    });

/// 收藏集列表（UI-P3-8）。
final FutureProvider<PageResult<KomgaCollection>> collectionsProvider =
    FutureProvider<PageResult<KomgaCollection>>((Ref ref) {
      return ref.watch(libraryRepositoryProvider).collections();
    });

/// 阅读列表。
final FutureProvider<PageResult<ReadList>> readListsProvider =
    FutureProvider<PageResult<ReadList>>((Ref ref) {
      return ref.watch(libraryRepositoryProvider).readLists();
    });

/// 收藏集里的系列。
final collectionSeriesProvider =
    FutureProvider.family<PageResult<Series>, String>((
      Ref ref,
      String collectionId,
    ) {
      return ref
          .watch(libraryRepositoryProvider)
          .collectionSeries(collectionId);
    });

/// 阅读列表里的书。
final readListBooksProvider = FutureProvider.family<PageResult<Book>, String>((
  Ref ref,
  String readListId,
) {
  return ref.watch(libraryRepositoryProvider).readListBooks(readListId);
});

/// 单本书的封面。
final bookCoverProvider = FutureProvider.family<Uint8List?, String>((
  Ref ref,
  String bookId,
) {
  return ref.watch(libraryRepositoryProvider).bookCover(bookId);
});

/// 最近添加的系列（"正在读"首页的第二块，UI-P2-6）。
///
/// 为什么用系列不用书：`GET /api/v1/series?sort=createdDate,desc` 是**已验证过**的
/// （`docs/series-queries.md`），而"按添加时间列书"的 `/api/v1/books` 没有验证过，
/// 也没有 fixture。先用验证过的端点做，等有服务器再补"最近添加的书"。
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

/// 继续阅读（在读过、还没读完的书）。空列表/失败都只是"不显示这一行"。
final ondeckProvider = FutureProvider<PageResult<Book>>((Ref ref) {
  return ref.watch(libraryRepositoryProvider).ondeck();
});

/// 书架一屏的状态。
///
/// 刻意不用 `AsyncValue`：书架同时存在"有数据 + 正在追加下一页 + 追加失败"
/// 这种组合态，`AsyncValue` 表达不了，硬塞会让 UI 里到处是 `hasValue && ...`。
class ShelfState {
  const ShelfState({
    this.series = const <Series>[],
    this.page = 0,
    this.totalElements = 0,
    this.hasMore = false,
    this.query = '',
    this.libraryId,
    this.sort,
    this.readStatus,
    this.view = ShelfView.grid,
    this.coverSize = ShelfCoverSize.medium,
    this.loading = true,
    this.loadingMore = false,
    this.failure,
    this.loadMoreFailure,
  });

  static const Object _unset = Object();

  final List<Series> series;

  /// 已加载到的 0 基页号。
  final int page;
  final int totalElements;
  final bool hasMore;
  final String query;
  final String? libraryId;

  /// 排序；null = 用服务端默认顺序。
  final SeriesSort? sort;

  /// 阅读状态筛选；null = 不筛选。
  final SeriesReadStatus? readStatus;

  /// 网格还是列表（UI-P2-7）。
  final ShelfView view;

  /// 网格封面档位（UI-P2-7）。
  final ShelfCoverSize coverSize;

  /// 首屏（或换库/换搜索词后的重新加载）进行中。
  final bool loading;

  /// 追加下一页进行中。
  final bool loadingMore;

  /// 首屏失败：此时 [series] 为空，整页显示错误态。
  final ShelfFailure? failure;

  /// 追加失败：已有内容保留，只在底部提示可重试。
  final ShelfFailure? loadMoreFailure;

  bool get isEmpty => series.isEmpty && !loading && failure == null;

  ShelfState copyWith({
    List<Series>? series,
    int? page,
    int? totalElements,
    bool? hasMore,
    String? query,
    Object? libraryId = _unset,
    Object? sort = _unset,
    Object? readStatus = _unset,
    ShelfView? view,
    ShelfCoverSize? coverSize,
    bool? loading,
    bool? loadingMore,
    ShelfFailure? failure,
    bool clearFailure = false,
    ShelfFailure? loadMoreFailure,
    bool clearLoadMoreFailure = false,
  }) => ShelfState(
    series: series ?? this.series,
    page: page ?? this.page,
    totalElements: totalElements ?? this.totalElements,
    hasMore: hasMore ?? this.hasMore,
    query: query ?? this.query,
    libraryId: identical(libraryId, _unset)
        ? this.libraryId
        : libraryId as String?,
    sort: identical(sort, _unset) ? this.sort : sort as SeriesSort?,
    readStatus: identical(readStatus, _unset)
        ? this.readStatus
        : readStatus as SeriesReadStatus?,
    view: view ?? this.view,
    coverSize: coverSize ?? this.coverSize,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
    loadMoreFailure: clearLoadMoreFailure
        ? null
        : (loadMoreFailure ?? this.loadMoreFailure),
  );
}

/// 书架控制器：分页、搜索、按库筛选，并处理请求竞态。
///
/// 竞态处理：每次加载递增 [_generation]，回包时对不上就直接丢弃。
/// 否则"快速切库 / 边搜索边下拉刷新"会让旧结果覆盖新结果（这类 bug 最难查）。
class ShelfController extends Notifier<ShelfState> {
  /// 搜索防抖：每敲一个字就发一次请求会把服务端和手机电池一起拖垮。
  static const Duration searchDebounce = Duration(milliseconds: 350);

  int _generation = 0;
  Timer? _debounce;

  @override
  ShelfState build() {
    // 订阅：会话/仓库变了要重新拉一遍（例如重新登录换了服务器）。
    ref.watch(libraryRepositoryProvider);
    ref.onDispose(() => _debounce?.cancel());
    // build() 还没返回时 state 尚未初始化，读它会抛 "uninitialized provider"，
    // 所以首屏加载必须推到下一个微任务。
    unawaited(Future<void>.microtask(() => _load(reset: true)));
    return const ShelfState();
  }

  LibraryRepository get _repository => ref.read(libraryRepositoryProvider);

  /// 下拉刷新 / 错误态重试。
  Future<void> refresh() {
    _debounce?.cancel();
    return _load(reset: true);
  }

  /// 从系列页/阅读器返回时用：**保留当前列表与滚动位置**，静默换新数据。
  ///
  /// 直接 `ref.invalidate(shelfProvider)` 会把列表清空、页面跳回顶部——
  /// 在大书库里读一本就回到顶部，体验很差（真机上撞到过）。
  Future<void> refreshInPlace() {
    _debounce?.cancel();
    return _load(reset: true, keepItems: true);
  }

  /// 滚到底部时追加下一页。
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    await _load(reset: false);
  }

  void selectLibrary(String? libraryId) {
    if (state.libraryId == libraryId) return;
    _debounce?.cancel();
    state = state.copyWith(
      libraryId: libraryId,
      series: const <Series>[],
      page: 0,
      totalElements: 0,
      hasMore: false,
      loading: true,
      clearFailure: true,
      clearLoadMoreFailure: true,
    );
    unawaited(_load(reset: true));
  }

  /// 输入搜索词（已防抖）。空串表示清除搜索。
  void search(String raw) {
    final query = raw.trim();
    if (query == state.query) return;
    state = state.copyWith(query: query);
    _debounce?.cancel();
    _debounce = Timer(searchDebounce, () => unawaited(_load(reset: true)));
  }

  /// 换排序：立刻重新拉第一页（排序结果顺序变了，追加已无意义）。
  void setSort(SeriesSort? sort) {
    if (state.sort == sort) return;
    _reloadWith(state.copyWith(sort: sort));
  }

  /// 换阅读状态筛选。
  void setReadStatus(SeriesReadStatus? status) {
    if (state.readStatus == status) return;
    _reloadWith(state.copyWith(readStatus: status));
  }

  /// 换呈现方式 / 封面档位（UI-P2-7）：**不重新发请求**，只改视图状态。
  void setView(ShelfView view) {
    if (state.view == view) return;
    state = state.copyWith(view: view);
  }

  void setCoverSize(ShelfCoverSize size) {
    if (state.coverSize == size) return;
    state = state.copyWith(coverSize: size);
  }

  /// 换查询条件后重新开始：清空列表、回到第一页，但保留新条件本身。
  void _reloadWith(ShelfState next) {
    _debounce?.cancel();
    state = next.copyWith(
      series: const <Series>[],
      page: 0,
      totalElements: 0,
      hasMore: false,
      loading: true,
      clearFailure: true,
      clearLoadMoreFailure: true,
    );
    unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset, bool keepItems = false}) async {
    final generation = ++_generation;
    final targetPage = reset ? 0 : state.page + 1;
    final keepVisible = keepItems && state.series.isNotEmpty;

    state = reset
        ? state.copyWith(
            loading: !keepVisible,
            clearFailure: true,
            clearLoadMoreFailure: true,
          )
        : state.copyWith(loadingMore: true, clearLoadMoreFailure: true);

    try {
      final result = await _repository.series(
        libraryId: state.libraryId,
        query: state.query,
        page: targetPage,
        sort: state.sort,
        readStatus: state.readStatus,
      );
      if (generation != _generation) return;

      state = state.copyWith(
        series: reset
            ? result.items
            : <Series>[...state.series, ...result.items],
        page: result.page,
        totalElements: result.totalElements,
        hasMore: result.hasMore,
        loading: false,
        loadingMore: false,
        clearFailure: true,
      );
    } on ShelfFailure catch (failure) {
      // 旧请求的错误同样要丢弃，否则会把新请求的 loading 态打成错误态。
      if (generation != _generation) return;
      // 已有内容时（下拉刷新失败）不清空书架：保留旧数据，只在底部提示可重试。
      state = reset && state.series.isEmpty
          ? state.copyWith(loading: false, failure: failure)
          : state.copyWith(
              loading: false,
              loadingMore: false,
              loadMoreFailure: failure,
            );
    }
  }
}

final NotifierProvider<ShelfController, ShelfState> shelfProvider =
    NotifierProvider<ShelfController, ShelfState>(ShelfController.new);
