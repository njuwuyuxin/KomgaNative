import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_args.dart';
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
                ),
              ),
            ),
            if (_query.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _SearchHint(text: l10n.searchHint),
              )
            else
              _SearchResults(query: _query),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final series = ref.watch(searchSeriesProvider(query));
    final books = ref.watch(searchBooksProvider(query));
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
        child: _SearchHint(text: l10n.searchNoResults(query)),
      );
    }

    return SliverList.list(
      // 悬浮导航条浮在内容上：结果列表末尾让开它。
      children: <Widget>[
        if (seriesItems.isNotEmpty) ...<Widget>[
          _Header(text: l10n.searchSeriesTab),
          for (final series in seriesItems)
            SeriesShelfRow(
              series: series,
              coverSize: ShelfCoverSize.small,
              onTap: () => context.push('/series/${series.id}'),
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
