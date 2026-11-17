import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 书架网格的列宽自适应：按可用宽度塞尽可能多的列，而不是按断点写死列数。
///
/// 好处：手机 2 列、平板 5 列、墨水屏 4 列都是同一条规则算出来的，
/// 页面里不需要再判断"是不是平板"，窗口拉伸时密度也自然跟着变。
SliverGridDelegate shelfGridDelegate() =>
    const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 190,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 0.6,
    );

/// 书架网格 + 下拉刷新 + 滚到底自动预取。
class ShelfGrid extends StatelessWidget {
  const ShelfGrid({
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    super.key,
  });

  /// 距底部还有多少像素就开始预取下一页。太大浪费流量，太小时用户会感到"卡一下"。
  static const double _prefetchExtent = 600;

  final ShelfState state;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification notification) {
          if (notification.metrics.extentAfter < _prefetchExtent) {
            unawaited(onLoadMore());
          }
          return false;
        },
        child: CustomScrollView(
          key: const Key('shelf-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.all(AppSpacing.md),
              sliver: SliverGrid(
                gridDelegate: shelfGridDelegate(),
                delegate: SliverChildBuilderDelegate((
                  BuildContext context,
                  int index,
                ) {
                  final series = state.series[index];
                  return SeriesShelfTile(
                    series: series,
                    onTap: () => context.push('/series/${series.id}'),
                  );
                }, childCount: state.series.length),
              ),
            ),
            SliverToBoxAdapter(
              child: ShelfPagingFooter(state: state, onRetry: onLoadMore),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
          ],
        ),
      ),
    );
  }
}

/// 底部状态：追加中 / 追加失败可重试 / 到底了。
class ShelfPagingFooter extends StatelessWidget {
  const ShelfPagingFooter({
    required this.state,
    required this.onRetry,
    super.key,
  });

  final ShelfState state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: AppSpacing.lg,
            height: AppSpacing.lg,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final failure = state.loadMoreFailure;
    if (failure != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Flexible(
              child: Text(
                failure.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              key: const Key('shelf-paging-retry'),
              onPressed: () => unawaited(onRetry()),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: Text(
            '${state.totalElements} series',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return const SizedBox(height: AppSpacing.md);
  }
}

/// 首屏加载时的骨架：只画色块，不做 shimmer（墨水屏上 shimmer 就是拖影）。
class ShelfSkeleton extends StatelessWidget {
  const ShelfSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return GridView.builder(
      key: const Key('shelf-skeleton'),
      padding: const EdgeInsets.all(AppSpacing.md),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: shelfGridDelegate(),
      // 两屏的量足够盖住首屏加载，多了纯属浪费。
      itemCount: 8,
      itemBuilder: (BuildContext context, int index) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
  }
}

/// 空态/错误态也要能下拉刷新：外面包一层"至少一屏高"的滚动容器。
///
/// 否则文案写着 "pull to refresh" 却根本拉不动——这种自相矛盾用户一定会撞上。
class RefreshableStatus extends StatelessWidget {
  const RefreshableStatus({
    required this.status,
    required this.onRefresh,
    super.key,
  });

  final Widget status;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: status,
            ),
          );
        },
      ),
    );
  }
}

/// 库筛选条。只有一个库时不占空间（选了也等于没选）。
class LibraryFilterBar extends ConsumerWidget {
  const LibraryFilterBar({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraries = ref.watch(librariesProvider);
    final items = switch (libraries) {
      AsyncData<List<Library>>(:final value) => value,
      _ => const <Library>[],
    };
    if (items.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: AppSpacing.xxl,
      child: ListView(
        key: const Key('library-filter'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (bool _) => onSelected(null),
            ),
          ),
          for (final library in items)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                label: Text(library.name),
                selected: selected == library.id,
                onSelected: (bool _) => onSelected(library.id),
              ),
            ),
        ],
      ),
    );
  }
}
