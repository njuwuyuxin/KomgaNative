import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/series_detail_args.dart';
import 'package:komga_native/src/widgets/reading_now_continue.dart';
import 'package:komga_native/src/widgets/series_hero_tag.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// "正在读"首页（UI-P2-6）。
///
/// 三块内容，从上到下：
/// 1. **大号继续阅读卡片**：Komga 的 ondeck 第一本（"上次看到哪"）；
/// 2. **最近添加**：按 `createdDate,desc` 的系列横向货架；
/// 3. **按库分组**：每个库一条横向货架。
///
/// 为什么是系列而不是书：`/api/v1/series?sort=createdDate,desc` 是验证过的端点，
/// "按添加时间列书"的那个没有 fixture（见 `docs/series-queries.md`），不猜。
///
/// 三块各自是独立请求，加载/失败要分开处理（FIX-05）：
/// - 加载中画骨架，**不**先渲染"还没有在读的书"再跳成卡片；
/// - 某一块的失败不牵连其他块：货架失败就少一行，继续卡失败给一句提示；
/// - 已有内容时刷新失败只在原处补一行小提示，不清空。
class ReadingNowScreen extends ConsumerWidget {
  const ReadingNowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final ondeck = ref.watch(ondeckProvider);
    final recent = ref.watch(recentSeriesProvider);
    final librariesAsync = ref.watch(librariesProvider);
    final libraries = librariesAsync.value ?? const <Library>[];

    Future<void> retryOndeck() async {
      ref.invalidate(ondeckProvider);
      await ref.read(ondeckProvider.future);
    }

    return Scaffold(
      body: GlassPageBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(ondeckProvider);
              ref.invalidate(recentSeriesProvider);
              for (final library in libraries) {
                ref.invalidate(libraryShelfProvider(library.id));
              }
            },
            child: CustomScrollView(
              key: const Key('reading-now-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: <Widget>[
                // 这一页没有标题栏：直接从"继续阅读"卡片开始。
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.sm),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: ReadingNowContinue(
                      // `?.items` 读的是分页结果；不写类型名是为了守住
                      // "界面层不 import komga_api" 这条分层约束。
                      books: ondeck.value?.items,
                      hasError: ondeck.hasError,
                      onRetry: retryOndeck,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xs,
                    ),
                    child: Text(
                      l10n.recentlyAdded,
                      style: AppTypography.of(context).title,
                    ),
                  ),
                ),
                _SeriesShelf(
                  key: const Key('reading-now-recent'),
                  heroScope: 'reading-now-recent',
                  series: recent.value,
                  hasError: recent.hasError,
                ),
                ..._libraryShelves(context, ref, libraries),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSizes.navBarClearance),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 每个库一条：标题 + 货架。库列表本身没到就整段不出现（下面的骨架已经占位）。
  List<Widget> _libraryShelves(
    BuildContext context,
    WidgetRef ref,
    List<Library> libraries,
  ) {
    final slivers = <Widget>[];
    for (final library in libraries) {
      final shelf = ref.watch(libraryShelfProvider(library.id));
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(library.name, style: AppTypography.of(context).title),
          ),
        ),
      );
      slivers.add(
        _SeriesShelf(
          key: Key('reading-now-library-${library.id}'),
          heroScope: 'reading-now-library-${library.id}',
          series: shelf.value,
          hasError: shelf.hasError,
        ),
      );
    }
    return slivers;
  }
}

/// 一条横向货架：系列卡片。
///
/// [heroScope] 区分同一页面上同一个系列的多份副本（"最近添加"与按库货架会重叠）。
/// 每条货架一个 scope，详情页通过 `SeriesDetailArgs` 记住被点的那一份，
/// 封面才会从手指下的卡片飞出去、退出时也飞回同一张。
class _SeriesShelf extends StatefulWidget {
  const _SeriesShelf({
    required this.series,
    required this.hasError,
    required this.heroScope,
    super.key,
  });

  /// null = 还没有可用结果（加载中或已失败）。
  final List<Series>? series;

  final bool hasError;
  final String heroScope;

  @override
  State<_SeriesShelf> createState() => _SeriesShelfState();
}

class _SeriesShelfState extends State<_SeriesShelf> {
  /// 同上：刷新失败时 Riverpod 会丢掉旧值，这一行不能因此整条消失。
  List<Series>? _lastGood;

  @override
  Widget build(BuildContext context) {
    final fresh = widget.series;
    if (fresh != null) _lastGood = fresh;
    final items = fresh ?? _lastGood;
    // 加载中：占住一条货架的高度，数据回来时标题不会整体跳一下。
    if (items == null) {
      return widget.hasError
          ? const SliverToBoxAdapter(child: SizedBox.shrink())
          : const SliverToBoxAdapter(child: ShelfRowSkeleton());
    }
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: SizedBox(
        height: AppSizes.shelfRowHeight + AppSpacing.md,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: items.length,
          separatorBuilder: (BuildContext context, int index) =>
              const SizedBox(width: AppSpacing.sm),
          itemBuilder: (BuildContext context, int index) {
            final item = items[index];
            final heroTag = seriesHeroTag(item.id, scope: widget.heroScope);
            return SizedBox(
              width: AppSizes.shelfCover.width + AppSpacing.xl,
              child: SeriesShelfTile(
                series: item,
                heroTag: heroTag,
                onTap: () => unawaited(
                  context.push(
                    '/series/${item.id}',
                    extra: SeriesDetailArgs(heroTag: heroTag),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
