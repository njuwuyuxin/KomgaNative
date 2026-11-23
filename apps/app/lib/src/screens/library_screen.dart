import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/pinned_series_provider.dart';
import 'package:komga_native/src/providers/shelf_selection_provider.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/collection_picker_sheet.dart';
import 'package:komga_native/src/widgets/offline_banner.dart';
import 'package:komga_native/src/widgets/phase_fade.dart';
import 'package:komga_native/src/widgets/shelf_active_filters.dart';
import 'package:komga_native/src/widgets/shelf_query_buttons.dart';
import 'package:komga_native/src/widgets/shelf_selection_bar.dart';
import 'package:komga_native/src/widgets/shelf_pinch_detector.dart';
import 'package:komga_native/src/widgets/shelf_side_rail.dart';
import 'package:komga_native/src/widgets/shelf_views.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:komga_native/src/providers/series_read_provider.dart';
import 'package:material_ui/material_ui.dart';

part 'library_screen_batch.dart';
part 'library_screen_shelf.dart';

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

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with _ShelfSlivers, _ShelfBatch {
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

  /// 是否走平板两栏布局（PLT-01）：只在 `WindowSizeClass.expanded` 下。
  ///
  /// 断点判断只在 `WindowSizeClass` 里做一次（AGENTS.md 架构不变量 6），
  /// 页面内部不再自己比宽度。
  bool _twoPane(BuildContext context) =>
      WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
      WindowSizeClass.expanded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);
    final selection = ref.watch(shelfSelectionProvider);
    final selecting = ref.read(shelfSelectionProvider.notifier);

    return Scaffold(
      body: Row(
        children: <Widget>[
          // 平板（≥1024）才显示左侧库导航（PLT-01）：手机上它会挤掉两列封面。
          if (_twoPane(context)) const ShelfSideRail(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                GlassPageBackground(
                  child: RefreshIndicator(
                    // 标题栏是钉住的浮层：下拉刷新的转圈要出现在它下面，不能被玻璃压住。
                    edgeOffset:
                        MediaQuery.paddingOf(context).top +
                        AppSizes.glassHeaderClearance,
                    onRefresh: _refresh,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification notification) {
                        if (state.hasMore &&
                            notification.metrics.extentAfter <
                                _prefetchExtent) {
                          unawaited(controller.loadMore());
                        }
                        return false;
                      },
                      child: ShelfPinchDetector(
                        enabled:
                            state.view == ShelfView.grid &&
                            state.series.isNotEmpty,
                        onPinch: _pinchCover,
                        child: CustomScrollView(
                          key: const Key('shelf-scroll'),
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: <Widget>[
                            // 顶部只保留有用的东西：搜索框 + 右侧三颗动作。
                            // 不再放页面标题——标题既不提供信息，又占掉一整行。
                            GlassHeaderSliver(
                              header: GlassHeader(
                                bar: selection.active
                                    ? ShelfSelectionBar(
                                        count: selection.ids.length,
                                        total: state.series.length,
                                        allSelected:
                                            state.series.isNotEmpty &&
                                            selection.ids.length ==
                                                state.series.length,
                                        onSelectAll: () => selecting.selectAll(
                                          state.series.map((Series s) => s.id),
                                        ),
                                        onClose: selecting.exit,
                                      )
                                    : Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: GlassSearchField(
                                              key: const Key(
                                                'shelf-search-field',
                                              ),
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
                            // 大标题 + 系列数（LIB-01）：跟内容一起滚走，不常驻占高度。
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  AppSpacing.md,
                                  AppSpacing.md,
                                  AppSpacing.xs,
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        l10n.libraryTitle,
                                        style: AppTypography.of(context)
                                            .largeTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Text(
                                      l10n.seriesCount(state.totalElements),
                                      key: const Key('shelf-count'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
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
                            // 生效中的筛选条件（排序/状态/库），可单独清除（LIB-01）。
                            const SliverToBoxAdapter(
                              child: ShelfActiveFilters(),
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
                                  child: SizedBox(
                                    height: AppSizes.navBarClearance,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // 多选批量条采用与底部 dock 相同的悬浮玻璃层逻辑：
                // 手机形态下 `AdaptiveShell` 的 `extendBody` 已将安全区底边距
                // 抬到 dock 顶部，这里经 `SafeArea` + `AppSpacing.sm` 直接浮在
                // dock 上方，不压缩滚动视口，原页面布局零位移。
                if (selection.active)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: ShelfBatchBar(
                          count: selection.ids.length,
                          busy: _batchBusy,
                          onMarkRead: () => _markSelected(read: true),
                          onMarkUnread: () => _markSelected(read: false),
                          extraLabel: l10n.batchAddToCollection,
                          extraIcon: Icons.collections_bookmark_outlined,
                          extraKey: const Key('shelf-batch-collection'),
                          onExtraAction: _addSelectedToCollection,
                        ),
                      ),
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

/// 书架顶部右侧动作：多选圆球 + 排序/筛选/视图三格液态玻璃胶囊。
///
/// 三颗菜单动作合进同一块玻璃胶囊，向下滚动悬浮在漫画封面上时依然清晰可辨。
class _LibraryActions extends StatelessWidget {
  const _LibraryActions();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const ShelfSelectButton(),
        const SizedBox(width: AppSpacing.xs),
        GlassSurface(
          shape: AppShapes.of(context, AppShapes.bar),
          child: const SizedBox(
            height: AppSizes.glassOrb,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ShelfSortButton(),
                  ShelfFilterButton(),
                  ShelfViewButton(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
