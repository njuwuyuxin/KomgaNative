import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/l10n/failure_text.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_args.dart';
import 'package:komga_native/src/widgets/load_more_footer.dart';
import 'package:komga_native/src/widgets/search_facets.dart';
import 'package:komga_native/src/widgets/series_book_row.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 搜索结果 Sliver（SCH-03 / ARC-12 增量分页 + 失败保留旧结果）。
class SearchResultsSliver extends ConsumerWidget {
  const SearchResultsSliver({
    required this.query,
    required this.readStatus,
    required this.tag,
    required this.onReadStatus,
    required this.onTag,
    required this.onClearFacets,
    super.key,
  });

  final String query;
  final SeriesReadStatus? readStatus;
  final String? tag;
  final ValueChanged<SeriesReadStatus?> onReadStatus;
  final ValueChanged<String?> onTag;
  final VoidCallback onClearFacets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final search = (query: query, readStatus: readStatus, tag: tag);
    final seriesProv = searchSeriesProvider(search);
    final booksProv = searchBooksProvider(search);
    final series = ref.watch(seriesProv);
    final books = ref.watch(booksProv);
    final seriesNotifier = ref.read(seriesProv.notifier);
    final booksNotifier = ref.read(booksProv.notifier);

    final seriesItems = series.value?.items ?? const <Series>[];
    final bookItems = books.value?.items ?? const <Book>[];
    final failed =
        series.hasError ||
        books.hasError ||
        seriesNotifier.loadMoreFailure != null ||
        booksNotifier.loadMoreFailure != null;

    if (seriesItems.isEmpty && bookItems.isEmpty) {
      if (failed) {
        final error =
            series.error ??
            books.error ??
            seriesNotifier.loadMoreFailure ??
            booksNotifier.loadMoreFailure;
        return SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text(l10n.failureTitle(failureKindOf(error)))),
        );
      }
      if (series.value == null || books.value == null) {
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _SearchHint(text: l10n.searchNoResults(query)),
      );
    }

    void more() {
      unawaited(seriesNotifier.loadMore());
      unawaited(booksNotifier.loadMore());
    }

    return SliverList.list(
      children: <Widget>[
        if (failed)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: Row(
              key: const Key('search-refresh-failure'),
              children: <Widget>[
                Icon(
                  Icons.cloud_off_outlined,
                  size: AppSizes.iconSm,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.searchRefreshFailed,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SearchFacets(
          query: query,
          readStatus: readStatus,
          tag: tag,
          onReadStatus: onReadStatus,
          onTag: onTag,
          onClear: onClearFacets,
        ),
        if (seriesItems.isNotEmpty) ...<Widget>[
          _Header(text: l10n.searchSeriesTab),
          for (final item in seriesItems)
            SeriesShelfRow(
              series: item,
              coverSize: ShelfCoverSize.small,
              onTap: () => context.push('/series/${item.id}'),
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
