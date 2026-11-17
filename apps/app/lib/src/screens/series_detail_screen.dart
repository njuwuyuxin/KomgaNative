import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/widgets/offline_banner.dart';
import 'package:komga_native/src/widgets/shelf_views.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情：头部（封面/进度）+ 书列表，点一本书进阅读器。
class SeriesDetailScreen extends ConsumerWidget {
  const SeriesDetailScreen({required this.seriesId, super.key});

  final String seriesId;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(seriesDetailProvider(seriesId));
    ref.invalidate(seriesBooksProvider(seriesId));
    await ref.read(seriesBooksProvider(seriesId).future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(seriesDetailProvider(seriesId));
    final books = ref.watch(seriesBooksProvider(seriesId));
    final series = detail.value;

    // 注意：Riverpod 3 里"首次加载失败"会表现为 AsyncLoading + hasError，
    // 用 `AsyncError` 模式匹配会掉进 loading 分支（踩过）。这里按 hasError/value 判断。
    final error = books.error;
    final page = books.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          series?.title ?? 'Series',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: <Widget>[
          OfflineBanner(onRetry: () => unawaited(_refresh(ref))),
          Expanded(
            child: switch ((error, page)) {
              (final Object failure, _) => _ErrorView(
                failure: failure,
                onRetry: () => unawaited(_refresh(ref)),
              ),
              (null, final PageResult<Book> data) => _BooksView(
                series: series,
                books: data,
                seriesId: seriesId,
                onRefresh: () => _refresh(ref),
              ),
              _ => const _BooksSkeleton(),
            },
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.failure, required this.onRetry});

  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = failure is ShelfFailure ? failure as ShelfFailure : null;
    return RefreshableStatus(
      onRefresh: () async => onRetry(),
      status: StatusView(
        key: const Key('series-error'),
        icon: Icons.cloud_off_outlined,
        title: message?.message ?? const UnexpectedFailure('').message,
        message: message?.hint,
        actionLabel: 'Retry',
        onAction: onRetry,
      ),
    );
  }
}

class _BooksView extends StatelessWidget {
  const _BooksView({
    required this.series,
    required this.books,
    required this.seriesId,
    required this.onRefresh,
  });

  final Series? series;
  final PageResult<Book> books;
  final String seriesId;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final truncated = books.items.length < books.totalElements;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        key: const Key('series-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: _SeriesHeader(series: series, seriesId: seriesId),
          ),
          if (books.items.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: StatusView(
                key: Key('series-empty'),
                icon: Icons.menu_book_outlined,
                title: 'No books yet',
                message: 'This series has no readable books in Komga yet.',
              ),
            )
          else
            SliverList.separated(
              itemCount: books.items.length,
              itemBuilder: (BuildContext context, int index) => _BookRow(
                book: books.items[index],
                seriesId: seriesId,
                direction: series?.readingDirection ?? ReadingDirection.unknown,
              ),
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
            ),
          if (truncated)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Showing ${books.items.length} of ${books.totalElements} books',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 头部：封面 + 标题 + 已读进度。
class _SeriesHeader extends ConsumerWidget {
  const _SeriesHeader({required this.series, required this.seriesId});

  final Series? series;
  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cover = ref.watch(seriesCoverProvider(seriesId));
    final bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final read = series?.booksReadCount ?? 0;
    final total = series?.booksCount ?? 0;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: SizedBox(
              width: AppSpacing.xxl * 2,
              height: AppSpacing.xxl * 3,
              child: bytes == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    )
                  : Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  series?.title ?? 'Series',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$read of $total read',
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
                    _directionLabel(series!.readingDirection),
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

  static String _directionLabel(ReadingDirection direction) =>
      switch (direction) {
        ReadingDirection.rightToLeft => 'Reads right to left',
        ReadingDirection.leftToRight => 'Reads left to right',
        ReadingDirection.vertical => 'Vertical (webtoon)',
        ReadingDirection.webtoon => 'Webtoon',
        ReadingDirection.unknown => '',
      };
}

/// 一本书：封图 + 标题 + 页数/已读状态，点进去读。
class _BookRow extends ConsumerWidget {
  const _BookRow({
    required this.book,
    required this.seriesId,
    required this.direction,
  });

  final Book book;
  final String seriesId;
  final ReadingDirection direction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cover = ref.watch(bookCoverProvider(book.id));
    final bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final completed = book.isCompleted;

    return ListTile(
      key: Key('book-${book.id}'),
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
      title: Text(
        book.number.isEmpty ? book.name : '#${book.number} · ${book.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        completed
            ? 'Read · ${book.pagesCount} pages'
            : '${book.pagesCount} pages',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(
        completed ? Icons.check_circle : Icons.chevron_right,
        color: completed
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      onTap: () async {
        await context.push(
          '/reader/${book.id}',
          extra: ReaderArgs(book: book, direction: direction),
        );
        // 从阅读器回来时进度已经变了：不刷新的话"读完还是 0 of N"（真机上撞到过）。
        ref.invalidate(seriesDetailProvider(seriesId));
        ref.invalidate(seriesBooksProvider(seriesId));
      },
    );
  }
}

class _BooksSkeleton extends StatelessWidget {
  const _BooksSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView.separated(
      key: const Key('series-skeleton'),
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: 6,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (BuildContext context, int index) => Row(
        children: <Widget>[
          Container(
            width: AppSpacing.xl,
            height: AppSpacing.xxl,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Container(
              height: AppSpacing.md,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
