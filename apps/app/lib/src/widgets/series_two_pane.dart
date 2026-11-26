import 'dart:async';

import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/widgets/phase_fade.dart';
import 'package:yomu/src/widgets/series_book_list.dart';
import 'package:yomu/src/widgets/series_header.dart';
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
    this.topPadding = 0,
    this.toolbar,
    this.filtered = false,
    this.selected = const <String>{},
    this.selecting = false,
    this.onToggleSelect,
    this.onMarkManyBooks,
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
  final double topPadding;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final OpenSeriesBook onOpenBook;

  /// 书列表上方的工具条（SER-01）；为空时不占高度。
  final Widget? toolbar;

  /// 当前是否带筛选（决定空态文案）。
  final bool filtered;

  /// 多选状态（SER-02）。
  final Set<String> selected;
  final bool selecting;
  final void Function(String bookId)? onToggleSelect;
  final Future<void> Function(List<String> bookIds, {required bool read})?
  onMarkManyBooks;

  /// 书比当前加载的多时"加载更多"（UI-P2-4）。
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      edgeOffset: topPadding,
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
              topPadding: topPadding,
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
              toolbar: toolbar,
              filtered: filtered,
              selected: selected,
              selecting: selecting,
              onToggleSelect: onToggleSelect,
              onMarkManyBooks: onMarkManyBooks,
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
    this.topPadding = 0,
    this.toolbar,
    this.filtered = false,
    this.selected = const <String>{},
    this.selecting = false,
    this.onToggleSelect,
    this.onMarkManyBooks,
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
  final double topPadding;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetry;
  final OpenSeriesBook onOpenBook;

  /// 书列表上方的工具条（SER-01）；为空时不占高度。
  final Widget? toolbar;

  /// 当前是否带筛选（决定空态文案）。
  final bool filtered;

  /// 多选状态（SER-02）。
  final Set<String> selected;
  final bool selecting;
  final void Function(String bookId)? onToggleSelect;
  final Future<void> Function(List<String> bookIds, {required bool read})?
  onMarkManyBooks;

  /// 书比当前加载的多时"加载更多"（UI-P2-4）。
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      edgeOffset: topPadding,
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
                topPadding: topPadding,
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
                if (topPadding > 0)
                  SliverToBoxAdapter(child: SizedBox(height: topPadding)),
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
