import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/book_download_button.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
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
    super.key,
  });

  final Series? series;
  final PageResult<Book> books;
  final String seriesId;
  final Future<void> Function() onRefresh;
  final OpenSeriesBook onOpenBook;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: const Key('series-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: SeriesHeader(series: series, seriesId: seriesId),
          ),
          ...seriesBookSlivers(
            context,
            books: books,
            series: series,
            onOpenBook: onOpenBook,
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
    super.key,
  });

  final Series? series;
  final PageResult<Book> books;
  final String seriesId;
  final Future<void> Function() onRefresh;
  final OpenSeriesBook onOpenBook;

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
              child: SeriesHeader(series: series, seriesId: seriesId),
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
    if (truncated)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            l10n.showingBooks(books.items.length, books.totalElements),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
  ];
}

/// 头部：封面 + 标题 + 已读进度。
class SeriesHeader extends ConsumerWidget {
  const SeriesHeader({required this.series, required this.seriesId, super.key});

  final Series? series;
  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = ref.watch(seriesCoverProvider(seriesId));
    final bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final read = series?.booksReadCount ?? 0;
    final total = series?.booksCount ?? 0;
    // Hero 的另一半：tag 必须和书架卡片上那个一模一样（UI-P2-2）。
    // 墨水屏不飞：灰阶屏上的共享元素只会变成一层拖影。
    final coverBox = SizedBox(
      width: AppSpacing.xxl * 2,
      height: AppSpacing.xxl * 3,
      child: bytes == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            )
          : CoverImage(bytes: bytes),
    );
    final coverShape = AppShapes.of(context, AppShapes.panel);
    final coverWidget = DecoratedBox(
      decoration: ShapeDecoration(
        shape: coverShape,
        shadows: AppShadows.of(context, AppShadows.cover),
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: coverShape),
        child: coverBox,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (AppTheme.isEink(theme))
            coverWidget
          else
            Hero(tag: seriesHeroTag(seriesId), child: coverWidget),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  series?.title ?? l10n.seriesFallbackTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.readOfTotal(read, total),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: LinearProgressIndicator(
                    value: series?.progress ?? 0,
                    minHeight: AppSpacing.xs,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                if (series != null &&
                    series!.readingDirection != ReadingDirection.unknown) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _directionLabel(l10n, series!.readingDirection),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _directionLabel(
    AppLocalizations l10n,
    ReadingDirection direction,
  ) => switch (direction) {
    ReadingDirection.rightToLeft => l10n.readsRightToLeft,
    ReadingDirection.leftToRight => l10n.readsLeftToRight,
    ReadingDirection.vertical => l10n.readsVertical,
    ReadingDirection.webtoon => l10n.readsWebtoon,
    ReadingDirection.unknown => '',
  };
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
                : Image.memory(bytes, fit: BoxFit.cover),
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
      ),
    );
  }
}
