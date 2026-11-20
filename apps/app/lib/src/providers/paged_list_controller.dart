import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 通用增量分页器（ARC-12）：
/// - 首屏请求 `page = 0`；
/// - `loadMore()` 只请求下一页 `page = current.page + 1`，并在客户端追加结果，消除 \(O(N^2)\) 全量重拉；
/// - 内置 `_generation` 竞态保护，丢弃过期请求；
/// - 追加失败保留已有列表不清空，并通过 [AsyncLoading.copyWithPrevious] 或 [loadMoreFailure] 暴露错误。
abstract class PagedListController<T> extends AsyncNotifier<PageResult<T>> {
  int _generation = 0;
  bool _loadingMore = false;
  ShelfFailure? _loadMoreFailure;

  /// 每页固定请求条数（各页必须保持相同 `size`，保证 Spring `page * size` 偏移精确衔接）。
  int get pageSize;

  bool get loadingMore => _loadingMore;
  ShelfFailure? get loadMoreFailure => _loadMoreFailure;

  /// 子类实现单页拉取（`page` 为 0 基页码）。
  Future<PageResult<T>> fetchPage(int page, int size);

  @override
  Future<PageResult<T>> build() async {
    _generation++;
    _loadingMore = false;
    _loadMoreFailure = null;
    return fetchPage(0, pageSize);
  }

  /// 追加下一页增量数据（`page = current.page + 1`）；已在加载或已无更多时忽略。
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || _loadingMore) return;
    if (current.items.length >= current.totalElements) return;

    final generation = ++_generation;
    final nextPage = current.page + 1;
    _loadingMore = true;
    _loadMoreFailure = null;

    try {
      final next = await fetchPage(nextPage, pageSize);
      if (!ref.mounted || generation != _generation) return;
      _loadingMore = false;
      state = AsyncData<PageResult<T>>(
        PageResult<T>(
          items: <T>[...current.items, ...next.items],
          totalElements: next.totalElements,
          page: next.page,
          size: pageSize,
        ),
      );
    } on ShelfFailure catch (failure) {
      if (!ref.mounted || generation != _generation) return;
      _loadingMore = false;
      _loadMoreFailure = failure;
      // 触发一次保留旧值的重建，使监听者在保留已有结果的同时感知翻页失败（SCH-03）。
      state = AsyncData<PageResult<T>>(
        PageResult<T>(
          items: List<T>.of(current.items),
          totalElements: current.totalElements,
          page: current.page,
          size: current.size,
        ),
      );
    } on Object {
      if (!ref.mounted || generation != _generation) return;
      _loadingMore = false;
    }
  }
}
