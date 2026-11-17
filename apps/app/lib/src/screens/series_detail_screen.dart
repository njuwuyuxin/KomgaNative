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
class SeriesDetailScreen extends ConsumerWidget {
  const SeriesDetailScreen({required this.seriesId, super.key});

  final String seriesId;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(seriesDetailProvider(seriesId));
    ref.invalidate(seriesBooksProvider(seriesId));
    await ref.read(seriesBooksProvider(seriesId).future);
  }

  /// 进阅读器；回来时刷新进度。不刷新的话"读完还是 0 of N"（真机上撞到过）。
  Future<void> _openBook(
    BuildContext context,
    WidgetRef ref,
    Book book,
    ReadingDirection direction,
  ) async {
    await context.push(
      '/reader/${book.id}',
      extra: ReaderArgs(book: book, direction: direction),
    );
    ref.invalidate(seriesDetailProvider(seriesId));
    ref.invalidate(seriesBooksProvider(seriesId));
  }

  /// 标记整系列已读/未读；失败时用 SnackBar 说明，不把详情页变成错误页。
  Future<void> _markSeriesRead(
    BuildContext context,
    WidgetRef ref, {
    required bool read,
  }) async {
    try {
      await ref.read(seriesReadProvider.notifier).setRead(seriesId, read: read);
    } on ShelfFailure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(seriesDetailProvider(seriesId));
    final books = ref.watch(seriesBooksProvider(seriesId));
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
                unawaited(_markSeriesRead(context, ref, read: value == 'read')),
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
          OfflineBanner(onRetry: () => unawaited(_refresh(ref))),
          Expanded(
            child: switch ((error, page)) {
              (final Object failure, _) => _ErrorView(
                failure: failure,
                onRetry: () => unawaited(_refresh(ref)),
              ),
              (null, final PageResult<Book> data) =>
                wide
                    ? SeriesTwoPane(
                        series: series,
                        books: data,
                        seriesId: seriesId,
                        onRefresh: () => _refresh(ref),
                        onOpenBook: (Book book, ReadingDirection direction) =>
                            _openBook(context, ref, book, direction),
                      )
                    : SeriesSinglePane(
                        series: series,
                        books: data,
                        seriesId: seriesId,
                        onRefresh: () => _refresh(ref),
                        onOpenBook: (Book book, ReadingDirection direction) =>
                            _openBook(context, ref, book, direction),
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
