import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/data/shelf_filter_preset.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';

/// 书架一屏的状态。
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
    this.presets = const <ShelfFilterPreset>[],
    this.loading = true,
    this.loadingMore = false,
    this.failure,
    this.loadMoreFailure,
  });

  static const Object _unset = Object();

  final List<Series> series;
  final int page;
  final int totalElements;
  final bool hasMore;
  final String query;
  final String? libraryId;
  final SeriesSort? sort;
  final SeriesReadStatus? readStatus;
  final ShelfView view;
  final ShelfCoverSize coverSize;
  final List<ShelfFilterPreset> presets;
  final bool loading;
  final bool loadingMore;
  final ShelfFailure? failure;
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
    List<ShelfFilterPreset>? presets,
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
    presets: presets ?? this.presets,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    failure: clearFailure ? null : (failure ?? this.failure),
    loadMoreFailure: clearLoadMoreFailure
        ? null
        : (loadMoreFailure ?? this.loadMoreFailure),
  );
}
