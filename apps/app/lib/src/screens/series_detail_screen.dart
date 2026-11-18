import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/series_read_provider.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/widgets/offline_banner.dart';
import 'package:komga_native/src/widgets/series_two_pane.dart';
import 'package:komga_native/src/widgets/shelf_views.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情：头部（封面/进度）+ 书列表，点一本书进阅读器。
///
/// 窄屏是"头部 + 列表"一条滚动流；宽屏（`WindowSizeClass.expanded`）换成
/// 左头部 / 右书列表两栏，具体布局在 `widgets/series_two_pane.dart`。
///
/// 为什么是 StatefulWidget：书列表要能"加载更多"（UI-P2-4 解除 100 本上限），
/// 而"要多少本"是**视图状态**（重进详情页从 100 本重新开始就够），
/// 所以放在页面里，请求本身仍然只发生在 Repository 层。
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({required this.seriesId, super.key});

  final String seriesId;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  /// 当前请求的书数；点"加载更多"加一页。
  int _size = 100;

  String get seriesId => widget.seriesId;

  SeriesBooksQuery get _booksQuery => (seriesId: seriesId, size: _size);

  Future<void> _refresh() async {
    ref.invalidate(seriesDetailProvider(seriesId));
    ref.invalidate(seriesBooksProvider);
    await ref.read(seriesBooksProvider(_booksQuery).future);
  }

  /// 加载更多：多要一页（`size` 变了就是一次新查询，客户端不拼列表）。
  void _loadMore() => setState(() => _size += kSeriesBooksPageSize);

  /// 进阅读器；回来时刷新进度。不刷新的话"读完还是 0 of N"（真机上撞到过）。
  Future<void> _openBook(Book book, ReadingDirection direction) async {
    await context.push(
      '/reader/${book.id}',
      extra: ReaderArgs(book: book, direction: direction),
    );
    ref.invalidate(seriesDetailProvider(seriesId));
    ref.invalidate(seriesBooksProvider);
  }

  /// 标记整系列已读/未读；失败时用 SnackBar 说明，不把详情页变成错误页。
  Future<void> _markSeriesRead({required bool read}) async {
    try {
      await ref.read(seriesReadProvider.notifier).setRead(seriesId, read: read);
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(seriesDetailProvider(seriesId));
    final books = ref.watch(seriesBooksProvider(_booksQuery));
    final series = detail.value;

    // 注意：Riverpod 3 里"首次加载失败"会表现为 AsyncLoading + hasError，
    // 用 `AsyncError` 模式匹配会掉进 loading 分支（踩过）。这里按 hasError/value 判断。
    final error = books.error;
    final page = books.value;
    final wide =
        WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.expanded;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          series?.title ?? l10n.seriesFallbackTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          PopupMenuButton<String>(
            key: const Key('series-mark-menu'),
            icon: const Icon(Icons.done_all),
            tooltip: l10n.markReadTooltip,
            onSelected: (String value) =>
                unawaited(_markSeriesRead(read: value == 'read')),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                key: const Key('series-mark-read'),
                value: 'read',
                child: Text(l10n.markAllRead),
              ),
              PopupMenuItem<String>(
                key: const Key('series-mark-unread'),
                value: 'unread',
                child: Text(l10n.markAllUnread),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          OfflineBanner(onRetry: () => unawaited(_refresh())),
          Expanded(
            // 三态之间交叉淡入（UI-P2-8）：这里的内容是 box 而不是 sliver，
            // 可以直接用 `AnimatedSwitcher`（书架页用 `PhaseFade`，见那边的注释）。
            child: AnimatedSwitcher(
              duration: AppMotion.of(context).standard,
              switchInCurve: AppMotion.of(context).standardCurve,
              switchOutCurve: AppMotion.of(context).exitCurve,
              child: KeyedSubtree(
                key: ValueKey<String>(
                  error != null
                      ? 'error'
                      : (page != null ? 'books' : 'loading'),
                ),
                child: switch ((error, page)) {
                  (final Object failure, _) => _ErrorView(
                    failure: failure,
                    onRetry: () => unawaited(_refresh()),
                  ),
                  (null, final PageResult<Book> data) =>
                    wide
                        ? SeriesTwoPane(
                            series: series,
                            books: data,
                            seriesId: seriesId,
                            onRefresh: _refresh,
                            onLoadMore: _loadMore,
                            onOpenBook: _openBook,
                          )
                        : SeriesSinglePane(
                            series: series,
                            books: data,
                            seriesId: seriesId,
                            onRefresh: _refresh,
                            onLoadMore: _loadMore,
                            onOpenBook: _openBook,
                          ),
                  _ => const _BooksSkeleton(),
                },
              ),
            ),
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
    final l10n = AppLocalizations.of(context);
    final message = failure is ShelfFailure ? failure as ShelfFailure : null;
    return RefreshableStatus(
      onRefresh: () async => onRetry(),
      status: StatusView(
        key: const Key('series-error'),
        icon: Icons.cloud_off_outlined,
        title: message?.message ?? const UnexpectedFailure('').message,
        message: message?.hint,
        actionLabel: l10n.retry,
        onAction: onRetry,
      ),
    );
  }
}

class _BooksSkeleton extends StatelessWidget {
  const _BooksSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        key: const Key('series-skeleton'),
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: 6,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(height: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) => const Row(
          children: <Widget>[
            SizedBox(
              width: AppSpacing.xl,
              height: AppSpacing.xxl,
              child: SkeletonBox(),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: SizedBox(height: AppSpacing.md, child: SkeletonBox()),
            ),
          ],
        ),
      ),
    );
  }
}
