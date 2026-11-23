import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/l10n/failure_text.dart';
import 'package:komga_native/src/screens/reader_args.dart';
import 'package:komga_native/src/screens/series_detail_args.dart';
import 'package:komga_native/src/widgets/load_more_footer.dart';
import 'package:komga_native/src/widgets/series_book_row.dart';
import 'package:komga_native/src/widgets/series_hero_tag.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集详情页的系列列表 sliver（支持左滑移出、行尾移出按钮、长按菜单）。
class CollectionSeriesSliver extends StatelessWidget {
  const CollectionSeriesSliver({
    required this.collectionId,
    required this.async,
    required this.hiddenIds,
    required this.onRetry,
    required this.onLoadMore,
    required this.onRemove,
    required this.onLongPressSeries,
    super.key,
  });

  final String collectionId;
  final AsyncValue<PageResult<Series>> async;
  final Set<String> hiddenIds;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final Future<bool> Function(Series series, {bool fromSwipe}) onRemove;
  final Future<void> Function(
    BuildContext context,
    Series series,
    String heroTag,
  )
  onLongPressSeries;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (async.hasError && !async.hasValue) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView(
          icon: Icons.cloud_off_outlined,
          title: l10n.failureTitle(failureKindOf(async.error)),
          actionLabel: l10n.retry,
          onAction: onRetry,
        ),
      );
    }
    final page = async.value;
    if (page == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final visible = <Series>[
      for (final s in page.items)
        if (!hiddenIds.contains(s.id)) s,
    ];
    if (visible.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView(
          icon: Icons.collections_bookmark_outlined,
          title: l10n.collectionsEmpty,
        ),
      );
    }
    return SliverList.list(
      key: const Key('collection-series-list'),
      children: <Widget>[
        for (final series in visible)
          Dismissible(
            key: ValueKey<String>('collection-dismiss-${series.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => onRemove(series, fromSwipe: true),
            background: const _SwipeRemoveBackground(
              icon: Icons.remove_circle_outline,
            ),
            child: Builder(
              builder: (BuildContext rowContext) {
                final heroTag = seriesHeroTag(
                  series.id,
                  scope: 'collection-$collectionId',
                );
                return SeriesShelfRow(
                  series: series,
                  coverSize: ShelfCoverSize.medium,
                  heroTag: heroTag,
                  onTap: () => context.push(
                    '/series/${series.id}',
                    extra: SeriesDetailArgs(heroTag: heroTag),
                  ),
                  onLongPress: () =>
                      unawaited(onLongPressSeries(rowContext, series, heroTag)),
                  trailing: IconButton(
                    key: Key('collection-remove-${series.id}'),
                    tooltip: l10n.removeFromCollection,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.remove_circle_outline,
                      size: AppSizes.iconSm,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => unawaited(onRemove(series)),
                  ),
                );
              },
            ),
          ),
        LoadMoreFooter(
          loaded: page.items.length,
          total: page.totalElements,
          unit: LoadMoreUnit.series,
          onLoadMore: onLoadMore,
        ),
      ],
    );
  }
}

/// 阅读列表详情页的书籍列表 sliver（支持左滑移出、行尾移出按钮、长按菜单）。
class ReadListBooksSliver extends StatelessWidget {
  const ReadListBooksSliver({
    required this.async,
    required this.hiddenIds,
    required this.onRetry,
    required this.onLoadMore,
    required this.onAfterRead,
    required this.onRemove,
    super.key,
  });

  final AsyncValue<PageResult<Book>> async;
  final Set<String> hiddenIds;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final VoidCallback onAfterRead;
  final Future<bool> Function(Book book, {bool fromSwipe}) onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (async.hasError && !async.hasValue) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView(
          icon: Icons.cloud_off_outlined,
          title: l10n.failureTitle(failureKindOf(async.error)),
          actionLabel: l10n.retry,
          onAction: onRetry,
        ),
      );
    }
    final page = async.value;
    if (page == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final visible = <Book>[
      for (final b in page.items)
        if (!hiddenIds.contains(b.id)) b,
    ];
    if (visible.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView(
          icon: Icons.list_alt_outlined,
          title: l10n.readListsEmpty,
        ),
      );
    }
    return SliverList.list(
      key: const Key('readlist-books-list'),
      children: <Widget>[
        for (final book in visible)
          Dismissible(
            key: ValueKey<String>('readlist-dismiss-${book.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => onRemove(book, fromSwipe: true),
            background: const _SwipeRemoveBackground(
              icon: Icons.playlist_remove,
            ),
            child: SeriesBookRow(
              book: book,
              showSeriesTitle: true,
              onOpen: () async {
                await context.push(
                  '/reader/${book.id}',
                  extra: ReaderArgs(book: book),
                );
                onAfterRead();
              },
              onRemoveFromReadList: () async {
                await onRemove(book);
              },
              trailingAction: IconButton(
                key: Key('readlist-remove-${book.id}'),
                tooltip: l10n.removeFromReadList,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.remove_circle_outline,
                  size: AppSizes.iconSm,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: () => unawaited(onRemove(book)),
              ),
            ),
          ),
        LoadMoreFooter(
          loaded: page.items.length,
          total: page.totalElements,
          unit: LoadMoreUnit.books,
          onLoadMore: onLoadMore,
        ),
      ],
    );
  }
}

class _SwipeRemoveBackground extends StatelessWidget {
  const _SwipeRemoveBackground({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.errorContainer,
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.lg),
          child: Icon(icon, color: theme.colorScheme.onErrorContainer),
        ),
      ),
    );
  }
}
