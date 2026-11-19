import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/data/app_settings.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/widgets/search_empty_state.dart';
import 'package:komga_native/src/widgets/search_facets.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_args.dart';
import 'package:komga_native/src/widgets/load_more_footer.dart';
import 'package:komga_native/src/widgets/series_book_row.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 全局搜索（UI-P3-9）：系列 + 书，一次输入两边都查。
///
/// 不新建索引：Komga 的 `/series?search=` 与 `/books?search=` 都由服务端 Lucene
/// 匹配标题/作者/标签，客户端只负责合并展示。防抖用 `AppMotion.emphasized`。
///
/// 顶部的搜索框**就是**标题栏：玻璃胶囊里直接嵌输入框（iOS 搜索页的形态），
/// 不再套一层 `AppBar` + `TextField`。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppMotion.of(context).emphasized, () {
      if (!mounted) return;
      final query = value.trim();
      setState(() => _query = query);
    });
  }

  /// 用户"确认"搜索（键盘上的搜索键）时才记历史。
  ///
  /// 不在防抖里记：那样打 "frieren" 的过程中会把 "fri"、"frie" 也存进去。
  void _onSubmitted(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    _remember(query);
    setState(() => _query = query);
  }

  void _remember(String query) {
    final store = ref.read(settingsStoreProvider);
    unawaited(store.update((AppSettings s) => s.withSearchTerm(query)));
    setState(
      () => _history = <String>[
        query,
        for (final item in _history)
          if (item != query) item,
      ].take(kSearchHistoryLimit).toList(),
    );
  }

  List<String> _history = const <String>[];

  /// 搜索筛选（SCH-02）：跟着这一次搜索走，换关键词不重置（用户可能想接着筛）。
  SeriesReadStatus? _readStatus;
  String? _tag;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    final settings = await ref.read(settingsStoreProvider).load();
    if (!mounted) return;
    setState(() => _history = settings.searchHistory);
  }

  /// 点历史/建议：回填输入框并立刻搜。
  void _pick(String term) {
    _debounce?.cancel();
    _controller.text = term;
    _remember(term);
    setState(() => _query = term);
  }

  void _removeHistory(String term) {
    unawaited(
      ref
          .read(settingsStoreProvider)
          .update((AppSettings s) => s.withoutSearchTerm(term)),
    );
    setState(
      () => _history = <String>[
        for (final item in _history)
          if (item != term) item,
      ],
    );
  }

  void _clearHistory() {
    unawaited(
      ref
          .read(settingsStoreProvider)
          .update((AppSettings s) => s.clearSearchHistory()),
    );
    setState(() => _history = const <String>[]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: GlassPageBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(
                bar: GlassSearchField(
                  key: const Key('search-field'),
                  controller: _controller,
                  hintText: l10n.searchHint,
                  clearLabel: l10n.closeSearch,
                  autofocus: true,
                  onChanged: _onChanged,
                  onSubmitted: _onSubmitted,
                ),
              ),
            ),
            if (_query.isEmpty)
              // 用 ToBoxAdapter 而不是 FillRemaining：空态里是 ListView，
              // 塞进 hasScrollBody:false 的 FillRemaining 会触发
              // "RenderViewport does not support intrinsics"。
              SliverToBoxAdapter(
                child: SearchEmptyState(
                  history: _history,
                  onPick: _pick,
                  onRemove: _removeHistory,
                  onClear: _clearHistory,
                ),
              )
            else
              _SearchResults(
                query: _query,
                readStatus: _readStatus,
                tag: _tag,
                onReadStatus: (SeriesReadStatus? value) =>
                    setState(() => _readStatus = value),
                onTag: (String? value) => setState(() => _tag = value),
                onClearFacets: () => setState(() {
                  _readStatus = null;
                  _tag = null;
                }),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerStatefulWidget {
  const _SearchResults({
    required this.query,
    required this.readStatus,
    required this.tag,
    required this.onReadStatus,
    required this.onTag,
    required this.onClearFacets,
  });

  final String query;

  /// 筛选（SCH-02）：服务端已验证的只有 read_status 与 tag。
  final SeriesReadStatus? readStatus;
  final String? tag;
  final ValueChanged<SeriesReadStatus?> onReadStatus;
  final ValueChanged<String?> onTag;
  final VoidCallback onClearFacets;

  @override
  ConsumerState<_SearchResults> createState() => _SearchResultsState();
}

class _SearchResultsState extends ConsumerState<_SearchResults> {
  /// 已请求的条数（FIX-08）：搜索以前固定取 20 条，第 21 条起静默消失。
  int _size = kListPageSize;

  @override
  void didUpdateWidget(_SearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了搜索词就从一页重新开始，别把上一次的"加载更多"带过去。
    if (oldWidget.query != widget.query) _size = kListPageSize;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final search = (
      query: widget.query,
      size: _size,
      readStatus: widget.readStatus,
      tag: widget.tag,
    );
    final series = ref.watch(searchSeriesProvider(search));
    final books = ref.watch(searchBooksProvider(search));
    final seriesItems = series.value?.items ?? const <Series>[];
    final bookItems = books.value?.items ?? const <Book>[];
    final loading = series.value == null || books.value == null;

    if (loading) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (series.hasError && books.hasError) {
      final error = series.error;
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Text(
            error is ShelfFailure ? error.message : l10n.errorGeneric,
          ),
        ),
      );
    }
    if (seriesItems.isEmpty && bookItems.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _SearchHint(text: l10n.searchNoResults(widget.query)),
      );
    }
    final more = () => setState(() => _size += kListPageSize);

    return SliverList.list(
      // 悬浮导航条浮在内容上：结果列表末尾让开它。
      children: <Widget>[
        SearchFacets(
          query: widget.query,
          readStatus: widget.readStatus,
          tag: widget.tag,
          onReadStatus: widget.onReadStatus,
          onTag: widget.onTag,
          onClear: widget.onClearFacets,
        ),
        if (seriesItems.isNotEmpty) ...<Widget>[
          _Header(text: l10n.searchSeriesTab),
          for (final series in seriesItems)
            SeriesShelfRow(
              series: series,
              coverSize: ShelfCoverSize.small,
              onTap: () => context.push('/series/${series.id}'),
            ),
          if (series.value != null)
            LoadMoreFooter(
              loaded: seriesItems.length,
              total: series.value!.totalElements,
              unit: LoadMoreUnit.series,
              onLoadMore: more,
            ),
        ],
        if (bookItems.isNotEmpty) ...<Widget>[
          _Header(text: l10n.searchBooksTab),
          for (final book in bookItems)
            SeriesBookRow(
              book: book,
              // 搜索结果脱离系列上下文：标题补上系列名（FIX-06）。
              showSeriesTitle: true,
              onOpen: () async {
                await context.push(
                  '/reader/${book.id}',
                  extra: ReaderArgs(book: book),
                );
              },
            ),
          if (books.value != null)
            LoadMoreFooter(
              loaded: bookItems.length,
              total: books.value!.totalElements,
              unit: LoadMoreUnit.books,
              onLoadMore: more,
            ),
        ],
        const SizedBox(height: AppSizes.navBarClearance),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(text, style: AppTypography.of(context).title),
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.search,
            size: AppSizes.iconLg,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(text, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
