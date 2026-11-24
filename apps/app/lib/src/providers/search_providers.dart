import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/library_providers.dart';

/// 搜索查询条件（SCH-02 / ARC-12：不含 `size`，由增量分页器按 `page = 0, 1...` 拉取）。
typedef SearchQuery = ({
  String query,
  SeriesReadStatus? readStatus,
  String? tag,
});

/// 每次切入或重点搜索页时自增，驱动常驻的 `SearchScreen` 重新聚焦弹出键盘。
class SearchFocusRequestNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final searchFocusRequestProvider =
    NotifierProvider<SearchFocusRequestNotifier, int>(
      SearchFocusRequestNotifier.new,
    );

/// 全局书搜索增量分页控制器（ARC-12）。
class SearchBooksController extends PagedListController<Book> {
  SearchBooksController(this.search);

  final SearchQuery search;

  @override
  int get pageSize => kListPageSize;

  @override
  Future<PageResult<Book>> fetchPage(int page, int size) => ref
      .watch(libraryRepositoryProvider)
      .searchBooks(search.query, page: page, size: size);
}

final searchBooksProvider =
    AsyncNotifierProvider.family<
      SearchBooksController,
      PageResult<Book>,
      SearchQuery
    >(SearchBooksController.new);

/// 全局系列搜索增量分页控制器（ARC-12）。
class SearchSeriesController extends PagedListController<Series> {
  SearchSeriesController(this.search);

  final SearchQuery search;

  @override
  int get pageSize => kListPageSize;

  @override
  Future<PageResult<Series>> fetchPage(int page, int size) => ref
      .watch(libraryRepositoryProvider)
      .series(
        query: search.query,
        page: page,
        size: size,
        readStatus: search.readStatus,
        tag: search.tag,
      );
}

final searchSeriesProvider =
    AsyncNotifierProvider.family<
      SearchSeriesController,
      PageResult<Series>,
      SearchQuery
    >(SearchSeriesController.new);

/// 搜索页可选的标签（SCH-02）：从未加标签筛选的前 50 条系列结果里聚合。
final searchTagFacetsProvider =
    FutureProvider.family<List<String>, SearchQuery>((
      Ref ref,
      SearchQuery q,
    ) async {
      final page = await ref
          .watch(libraryRepositoryProvider)
          .series(query: q.query, size: 50);
      final counts = <String, int>{};
      for (final series in page.items) {
        for (final tag in series.tags) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
      final tags = counts.keys.toList()
        ..sort((String a, String b) {
          final byCount = counts[b]!.compareTo(counts[a]!);
          return byCount != 0 ? byCount : a.compareTo(b);
        });
      return tags.take(6).toList();
    });
