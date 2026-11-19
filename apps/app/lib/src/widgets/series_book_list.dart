import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/widgets/series_book_row.dart';
import 'package:material_ui/material_ui.dart';

/// 打开一本书（带上系列阅读方向），由 `SeriesDetailScreen` 负责路由与刷新。
typedef OpenSeriesBook = Future<void> Function(
  Book book,
  ReadingDirection direction,
);

/// 书列表区域的稳定状态标识（给 `PhaseFade` 用）。
///
/// 只有首屏**没有旧数据**时才是 `loading`：刷新（下拉 / 从阅读器返回）期间
/// Riverpod 会保留上一次的 value，列表继续显示旧内容，不闪骨架。
String seriesBooksPhase({
  required PageResult<Book>? books,
  required Object? failure,
}) {
  if (failure != null) return 'error';
  if (books == null) return 'loading';
  return books.items.isEmpty ? 'empty' : 'content';
}

/// 书列表区域的三态 sliver：加载骨架 / 错误 / 内容。
///
/// 头部（含 Hero 封面）不在这里，由页面固定放在列表上方——首次打开时头部
/// 第一帧就要在，书列表慢一步到不影响封面动画。
List<Widget> seriesBookPhaseSlivers(
  BuildContext context, {
  required PageResult<Book>? books,
  required Object? failure,
  required Series? series,
  required OpenSeriesBook onOpenBook,
  required VoidCallback onRetry,
  VoidCallback? onLoadMore,
  Widget? toolbar,
  bool filtered = false,
}) {
  // 失败优先：与改造前一致（刷新失败也会显示错误态，不静默保留旧列表）。
  if (failure != null) {
    return <Widget>[
      SliverFillRemaining(
        hasScrollBody: false,
        child: _SeriesBooksError(failure: failure, onRetry: onRetry),
      ),
    ];
  }
  final page = books;
  if (page == null) {
    return const <Widget>[SliverToBoxAdapter(child: SeriesBooksSkeleton())];
  }
  return _seriesBookSlivers(
    context,
    books: page,
    series: series,
    onOpenBook: onOpenBook,
    onLoadMore: onLoadMore,
    toolbar: toolbar,
    filtered: filtered,
  );
}

/// 书列表的 sliver 片段：窄屏与宽屏共用，避免两套空态/截断文案。
List<Widget> _seriesBookSlivers(
  BuildContext context, {
  required PageResult<Book> books,
  required Series? series,
  required OpenSeriesBook onOpenBook,
  VoidCallback? onLoadMore,
  Widget? toolbar,
  bool filtered = false,
}) {
  final l10n = AppLocalizations.of(context);
  final theme = Theme.of(context);
  final truncated = books.items.length < books.totalElements;
  final direction = series?.readingDirection ?? ReadingDirection.unknown;

  return <Widget>[
    if (toolbar != null) SliverToBoxAdapter(child: toolbar),
    if (books.items.isEmpty)
      SliverFillRemaining(
        hasScrollBody: false,
        child: StatusView(
          key: const Key('series-empty'),
          icon: Icons.menu_book_outlined,
          // 有筛选时"这个系列还没有书"是错的：书在，只是被筛掉了。
          title: filtered ? l10n.noMatchingBooks : l10n.noBooksYet,
          message: filtered ? l10n.noMatchingBooksHint : l10n.noBooksHint,
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

/// 书列表首屏骨架（UI-P2-8）：微光扫过的行占位。
///
/// 墨水屏 / "减少动态效果"下 [Shimmer] 退化成静态色块（灰阶屏上微光就是拖影）。
class SeriesBooksSkeleton extends StatelessWidget {
  const SeriesBooksSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        key: const Key('series-skeleton'),
        children: <Widget>[
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: AppSpacing.xl,
                    height: AppSpacing.xxl,
                    child: SkeletonBox(),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: SizedBox(
                      height: AppSpacing.md,
                      child: SkeletonBox(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 书列表加载失败。头部仍然在（封面/标题照常显示），只有列表区变成错误态。
class _SeriesBooksError extends StatelessWidget {
  const _SeriesBooksError({required this.failure, required this.onRetry});

  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final message = failure is ShelfFailure ? failure as ShelfFailure : null;
    return StatusView(
      key: const Key('series-error'),
      icon: Icons.cloud_off_outlined,
      title: message?.message ?? const UnexpectedFailure('').message,
      message: message?.hint,
      actionLabel: l10n.retry,
      onAction: onRetry,
    );
  }
}
