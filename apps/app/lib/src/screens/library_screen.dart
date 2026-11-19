import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/offline_banner.dart';
import 'package:komga_native/src/widgets/phase_fade.dart';
import 'package:komga_native/src/widgets/shelf_query_buttons.dart';
import 'package:komga_native/src/widgets/shelf_pinch_detector.dart';
import 'package:komga_native/src/widgets/shelf_views.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 书架页：真实 `/api/v1/series` 数据 + 封面 + 分页 + 搜索 + 按库筛选。
///
/// 整页是**一条** `CustomScrollView`：顶部是钉住的悬浮玻璃标题栏
/// （与底部导航条同一材质、同一留白），搜索框 / 库筛选都挂在同一条滚动流里。
/// 往下滑看封面时标题栏留在顶上，内容从玻璃下面穿过去——iOS 26 的观感。
///
/// 状态机在 [ShelfController] 里，这一层只负责把状态画出来并派发意图；
/// 视图组件在 `widgets/shelf_views.dart`（拆开是为了守住单文件行数上限）。
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  /// 距底部还有多少像素就开始预取下一页。太大浪费流量，太小时用户会感到"卡一下"。
  static const double _prefetchExtent = 600;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() {
    // "正在读"页也读 ondeck：刷新书架时顺手让它重新取（两页共享同一份数据）。
    ref.invalidate(ondeckProvider);
    return ref.read(shelfProvider.notifier).refresh();
  }

  /// 双指捏合换封面档位（UI-P2-7）。只在网格视图生效；到顶/到底不循环。
  void _pinchCover(int delta) {
    final state = ref.read(shelfProvider);
    const values = ShelfCoverSize.values;
    final current = values.indexOf(state.coverSize);
    final next = (current + delta).clamp(0, values.length - 1);
    if (next == current) return;
    unawaited(AppHaptics.selection());
    ref.read(shelfProvider.notifier).setCoverSize(values[next]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);

    return Scaffold(
      body: GlassPageBackground(
        // Android 的拉伸过度滚动会给整条滚动层加一个 Transform，而液态玻璃
        // 着色器按屏幕坐标采样背景；下拉刷新时就会读到被变换过的空图层，
        // 玻璃变黑。这里关掉过度滚动的拉伸/辉光（下拉刷新由 RefreshIndicator
        // 自己处理，不依赖那个效果）。
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
          child: RefreshIndicator(
            // 标题栏是钉住的浮层：下拉刷新的转圈要出现在它下面，不能被玻璃压住。
            edgeOffset:
                MediaQuery.paddingOf(context).top +
                AppSizes.glassHeaderClearance,
            onRefresh: _refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification notification) {
                if (state.hasMore &&
                    notification.metrics.extentAfter < _prefetchExtent) {
                  unawaited(controller.loadMore());
                }
                return false;
              },
              child: ShelfPinchDetector(
                enabled:
                    state.view == ShelfView.grid && state.series.isNotEmpty,
                onPinch: _pinchCover,
                child: CustomScrollView(
                  key: const Key('shelf-scroll'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: <Widget>[
                    // 顶部只保留有用的东西：搜索框 + 右侧三颗动作。
                    // 不再放页面标题——标题既不提供信息，又占掉一整行。
                    GlassHeaderSliver(
                      header: GlassHeader(
                        bar: Row(
                          children: <Widget>[
                            Expanded(
                              child: GlassSearchField(
                                key: const Key('shelf-search-field'),
                                controller: _searchController,
                                hintText: l10n.searchSeriesHint,
                                clearLabel: l10n.closeSearch,
                                onChanged: controller.search,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            const _LibraryActions(),
                          ],
                        ),
                      ),
                    ),
                    // 断网时提示"看的是缓存"，并给一次重新联网的机会。
                    SliverToBoxAdapter(
                      child: OfflineBanner(
                        onRetry: () => unawaited(_refresh()),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: LibraryFilterBar(
                        selected: state.libraryId,
                        onSelected: controller.selectLibrary,
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.sm),
                    ),
                    PhaseFade(
                      phase: _phaseOf(state),
                      slivers: <Widget>[
                        ..._shelfSlivers(l10n, state, controller),
                        // 底部留白：悬浮导航条压在内容之上，最后一行要能让开它。
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppSizes.navBarClearance),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 三态的稳定标识：只有它变了才播一次入场淡入。
  ///
  /// 用"加载中/空/错/内容"四档而不是整份 state：列表滚动、追加下一页
  /// 都不该触发一次全屏淡入。
  String _phaseOf(ShelfState state) {
    if (state.loading && state.series.isEmpty) return 'loading';
    if (state.failure != null && state.series.isEmpty) return 'error';
    if (state.isEmpty) return 'empty';
    return 'content';
  }

  /// 骨架 / 空错 / 内容三态，各自是 sliver（三态之间交叉淡入，UI-P2-8）。
  List<Widget> _shelfSlivers(
    AppLocalizations l10n,
    ShelfState state,
    ShelfController controller,
  ) {
    if (state.loading && state.series.isEmpty) {
      return <Widget>[const SliverFillRemaining(child: ShelfSkeleton())];
    }
    final failure = state.failure;
    if (failure != null && state.series.isEmpty) {
      final needsSignIn = failure is AuthFailure;
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: StatusView(
            key: const Key('shelf-error'),
            icon: Icons.cloud_off_outlined,
            title: failure.message,
            message: failure.hint,
            actionLabel: needsSignIn ? l10n.signOut : l10n.retry,
            onAction: needsSignIn
                ? () => ref.read(sessionProvider.notifier).signOut()
                : () => unawaited(_refresh()),
          ),
        ),
      ];
    }
    if (state.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: StatusView(
            key: const Key('shelf-empty'),
            icon: Icons.auto_stories_outlined,
            title: state.query.isEmpty ? l10n.noSeriesYet : l10n.noMatches,
            message: state.query.isEmpty
                ? l10n.emptyShelfHint
                : l10n.noSearchMatchesHint,
          ),
        ),
      ];
    }
    return <Widget>[
      // 网格 / 列表（UI-P2-7）：两种视图共用同一个 `state.series`，
      // 切换只是换 sliver 的类型，不重新请求。
      if (state.view == ShelfView.grid)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          sliver: SliverGrid(
            gridDelegate: shelfGridDelegate(state.coverSize),
            delegate: SliverChildBuilderDelegate((
              BuildContext context,
              int index,
            ) {
              final series = state.series[index];
              return SeriesShelfTile(
                series: series,
                onTap: () => unawaited(_openSeries(series)),
              );
            }, childCount: state.series.length),
          ),
        )
      else
        SliverList(
          delegate: SliverChildBuilderDelegate((
            BuildContext context,
            int index,
          ) {
            final series = state.series[index];
            return SeriesShelfRow(
              key: Key('series-${series.id}'),
              series: series,
              coverSize: state.coverSize,
              onTap: () => unawaited(_openSeries(series)),
            );
          }, childCount: state.series.length),
        ),
      SliverToBoxAdapter(
        child: ShelfPagingFooter(
          state: state,
          onRetry: () => controller.loadMore(),
        ),
      ),
    ];
  }

  /// 进系列页；回来时原地刷新进度（别把列表清空跳回顶部）。
  Future<void> _openSeries(Series series) async {
    await context.push('/series/${series.id}');
    await ref.read(shelfProvider.notifier).refreshInPlace();
  }
}

/// 书架顶部右侧的三颗动作：排序 / 筛选 / 视图。
///
/// 装进一条与搜索框同高的玻璃胶囊，和搜索框并排悬浮；没有标题文字，
/// 视觉重心留给封面。三条动作各 44×44，加起来仍比原来的整条标题栏省一行。
class _LibraryActions extends StatelessWidget {
  const _LibraryActions();

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      shape: AppShapes.of(context, AppShapes.bar),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ShelfSortButton(),
            ShelfFilterButton(),
            ShelfViewButton(),
          ],
        ),
      ),
    );
  }
}
