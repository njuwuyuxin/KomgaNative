import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/library_repository.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
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
      );
      ref.onDispose(komga.close);
      return KomgaLibraryRepository(komga);
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

/// 系列下的书。
///
/// 一次要 100 本：绝大多数系列到不了，省掉一整套分页状态机；
/// 真超过 100 本时 UI 会明说"只显示了前 N 本"，不装作全部都在。
final seriesBooksProvider = FutureProvider.family<PageResult<Book>, String>((
  Ref ref,
  String seriesId,
) {
  return ref.watch(libraryRepositoryProvider).books(seriesId);
});

/// 单本书的封面。
final bookCoverProvider = FutureProvider.family<Uint8List?, String>((
  Ref ref,
  String bookId,
) {
  return ref.watch(libraryRepositoryProvider).bookCover(bookId);
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
