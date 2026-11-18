import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/book_read_provider.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/book_download_button.dart';
import 'package:komga_native/src/widgets/context_menu.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:komga_native/src/widgets/series_header.dart';
import 'package:material_ui/material_ui.dart';

/// 打开一本书（带上系列阅读方向），由 `SeriesDetailScreen` 负责路由与刷新。
typedef OpenSeriesBook = Future<void> Function(
  Book book,
  ReadingDirection direction,
);

/// 窄屏系列详情：头部与书列表放在同一条滚动流里（保持不变）。
class SeriesSinglePane extends StatelessWidget {
  const SeriesSinglePane({
    required this.series,
    required this.books,
    required this.seriesId,
    required this.onRefresh,
    required this.onOpenBook,
    this.onLoadMore,
    super.key,
  });

  final Series? series;
  final PageResult<Book> books;
  final String seriesId;
  final Future<void> Function() onRefresh;
  final OpenSeriesBook onOpenBook;

  /// 书比当前加载的多时"加载更多"（UI-P2-4）。
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: const Key('series-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: SeriesHeader(
              series: series,
              seriesId: seriesId,
              books: books.items,
              onOpenBook: (Book book) => unawaited(
                onOpenBook(
                  book,
                  series?.readingDirection ?? ReadingDirection.unknown,
                ),
              ),
            ),
          ),
          ...seriesBookSlivers(
            context,
            books: books,
            series: series,
            onOpenBook: onOpenBook,
            onLoadMore: onLoadMore,
          ),
        ],
      ),
    );
  }
}

/// 宽屏（`WindowSizeClass.expanded`）系列详情：左头部 / 右书列表。
///
/// 只对 ≥1024 生效，不是所有非 compact 都两栏：758×1024 的墨水屏、844×390 的
/// 横屏手机用两栏会把书列表挤成一条缝，竖向空间也不够。
class SeriesTwoPane extends StatelessWidget {
  const SeriesTwoPane({
    required this.series,
    required this.books,
    required this.seriesId,
    required this.onRefresh,
    required this.onOpenBook,
    this.onLoadMore,
    super.key,
  });

  final Series? series;
  final PageResult<Book> books;
  final String seriesId;
  final Future<void> Function() onRefresh;
  final OpenSeriesBook onOpenBook;

  /// 书比当前加载的多时"加载更多"（UI-P2-4）。
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: SeriesHeader(
                series: series,
                seriesId: seriesId,
                books: books.items,
                onOpenBook: (Book book) => unawaited(
                  onOpenBook(
                    book,
                    series?.readingDirection ?? ReadingDirection.unknown,
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: AppSizes.hairline),
          Expanded(
            flex: 3,
            child: CustomScrollView(
              key: const Key('series-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: seriesBookSlivers(
                context,
                books: books,
                series: series,
                onOpenBook: onOpenBook,
                onLoadMore: onLoadMore,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 书列表的 sliver 片段：窄屏与宽屏共用，避免两套空态/截断文案。
List<Widget> seriesBookSlivers(
  BuildContext context, {
  required PageResult<Book> books,
  required Series? series,
  required OpenSeriesBook onOpenBook,
  VoidCallback? onLoadMore,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final truncated = books.items.length < books.totalElements;
  final direction = series?.readingDirection ?? ReadingDirection.unknown;

  return <Widget>[
    if (books.items.isEmpty)
      SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView(
          key: const Key('series-empty'),
          icon: Icons.menu_book_outlined,
          title: l10n.noBooksYet,
          message: l10n.noBooksHint,
        ),
      )
    else
      SliverList.separated(
        itemCount: books.items.length,
        itemBuilder: (BuildContext context, int index) => SeriesBookRow(
          book: books.items[index],
          onOpen: () => onOpenBook(books.items[index], direction),
        ),
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: AppSizes.hairline),
      ),
    // 还有更多就让用户拉下来（UI-P2-4 解除 100 本上限）：以前这里只有一句
    // "只显示了前 N 本"，大系列（几百本）根本读不到后面的。
    if (truncated)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: onLoadMore == null
              ? Text(
                  l10n.showingBooks(books.items.length, books.totalElements),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : Center(
                  child: OutlinedButton.icon(
                    key: const Key('series-load-more'),
                    onPressed: () => onLoadMore(),
                    icon: const Icon(Icons.expand_more),
                    label: Text(
                      l10n.showingBooks(
                        books.items.length,
                        books.totalElements,
                      ),
                    ),
                  ),
                ),
        ),
      ),
  ];
}

/// 一本书：封图 + 标题 + 页数/已读状态，点进去读。
///
/// 整行是一个按钮；读屏只播报「标题 + 页数/已读」，下载按钮仍是独立控件。
class SeriesBookRow extends ConsumerWidget {
  const SeriesBookRow({required this.book, required this.onOpen, super.key});

  final Book book;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = ref.watch(bookCoverProvider(book.id));
    final bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final completed = book.isCompleted;
    final title = book.number.isEmpty
        ? book.name
        : '#${book.number} · ${book.name}';
    final status = completed
        ? l10n.bookReadPages(book.pagesCount)
        : l10n.bookPages(book.pagesCount);

    return Semantics(
      key: Key('book-${book.id}'),
      container: true,
      button: true,
      label: '$title, $status',
      onTap: () => unawaited(onOpen()),
      child: PressableScale(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: SizedBox(
              width: AppSpacing.xl,
              height: AppSpacing.xxl,
              child: bytes == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    )
                  : CoverImage(bytes: bytes),
            ),
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              BookDownloadButton(book: book),
              Icon(
                completed ? Icons.check_circle : Icons.chevron_right,
                color: completed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          onTap: () => unawaited(onOpen()),
          onLongPress: () => unawaited(_showMenu(context, ref)),
        ),
      ),
    );
  }

  /// 长按一本书：标记已读 / 未读（UI-P2-5 顺带补上的单本书标记）。
  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    unawaited(AppHaptics.light());
    final action = await showContextMenu<bool>(
      context: context,
      anchor: context,
      entries: <ContextMenuEntry<bool>>[
        ContextMenuEntry(
          value: true,
          label: l10n.bookMarkRead,
          icon: Icons.done,
        ),
        ContextMenuEntry(
          value: false,
          label: l10n.bookMarkUnread,
          icon: Icons.remove_done,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    await ref
        .read(bookReadProvider.notifier)
        .setRead(book.id, read: action, pagesCount: book.pagesCount);
    if (!context.mounted) return;
    // 书列表是"本地进度叠加"出来的，改完要让详情重新取一遍。
    ref.invalidate(seriesBooksProvider);
    ref.invalidate(seriesDetailProvider(book.seriesId));
  }
}
