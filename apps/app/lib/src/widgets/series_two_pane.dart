import 'dart:async';

import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/widgets/phase_fade.dart';
import 'package:komga_native/src/widgets/series_book_list.dart';
import 'package:komga_native/src/widgets/series_header.dart';
import 'package:material_ui/material_ui.dart';

/// 窄屏系列详情：头部与书列表放在同一条滚动流里。
///
/// 头部**不在**三态切换之内：首次打开时它第一帧就渲染（封面 + Hero 落点），
/// 书列表区自己负责骨架 / 错误 / 内容三态（`PhaseFade` 只做入场淡入，
/// sliver 不能像 box 那样交叉淡入，理由见 `phase_fade.dart`）。
class SeriesSinglePane extends StatelessWidget {
  const SeriesSinglePane({
    required this.series,
    required this.books,
    required this.failure,
    required this.metadataLoading,
    required this.seriesId,
    required this.heroTag,
    required this.onRefresh,
    required this.onRetry,
    required this.onOpenBook,
    this.onLoadMore,
    super.key,
  });

  final Series? series;
  final PageResult<Book>? books;
  final Object? failure;
  final bool metadataLoading;
  final String seriesId;

  /// 封面 Hero tag（由 `SeriesDetailArgs` 带过来，见 `seriesHeroTag`）。
  final String heroTag;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
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
              heroTag: heroTag,
              books: books?.items,
              metadataLoading: metadataLoading,
              booksLoading: books == null && failure == null,
              onOpenBook: (Book book) => unawaited(
                onOpenBook(
                  book,
                  series?.readingDirection ?? ReadingDirection.unknown,
                ),
              ),
            ),
          ),
          PhaseFade(
            phase: seriesBooksPhase(books: books, failure: failure),
            slivers: seriesBookPhaseSlivers(
              context,
              books: books,
              failure: failure,
              series: series,
              onOpenBook: onOpenBook,
              onRetry: onRetry,
              onLoadMore: onLoadMore,
            ),
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
    required this.failure,
    required this.metadataLoading,
    required this.seriesId,
    required this.heroTag,
    required this.onRefresh,
    required this.onRetry,
    required this.onOpenBook,
    this.onLoadMore,
    super.key,
  });

  final Series? series;
  final PageResult<Book>? books;
  final Object? failure;
  final bool metadataLoading;
  final String seriesId;

  /// 封面 Hero tag（由 `SeriesDetailArgs` 带过来，见 `seriesHeroTag`）。
  final String heroTag;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
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
                heroTag: heroTag,
                books: books?.items,
                metadataLoading: metadataLoading,
                booksLoading: books == null && failure == null,
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
              slivers: <Widget>[
                PhaseFade(
                  phase: seriesBooksPhase(books: books, failure: failure),
                  slivers: seriesBookPhaseSlivers(
                    context,
                    books: books,
                    failure: failure,
                    series: series,
                    onOpenBook: onOpenBook,
                    onRetry: onRetry,
                    onLoadMore: onLoadMore,
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
