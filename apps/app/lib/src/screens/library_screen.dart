import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/data/shelf_view_options.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/local_catalog_mutator_provider.dart';
import 'package:yomu/src/providers/local_folder_tree_provider.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/shelf_selection_provider.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu/src/widgets/collection_picker_sheet.dart';
import 'package:yomu/src/widgets/local_folder_tree_sliver.dart';
import 'package:yomu/src/widgets/local_metadata_sheets.dart';
import 'package:yomu/src/widgets/offline_banner.dart';
import 'package:yomu/src/widgets/phase_fade.dart';
import 'package:yomu/src/widgets/shelf_active_filters.dart';
import 'package:yomu/src/widgets/shelf_header_bar.dart';
import 'package:yomu/src/widgets/shelf_pinch_detector.dart';
import 'package:yomu/src/widgets/shelf_side_rail.dart';
import 'package:yomu/src/widgets/shelf_views.dart';
import 'package:yomu/src/widgets/series_shelf_tile.dart';
import 'package:yomu/src/providers/series_read_provider.dart';
import 'package:yomu/src/widgets/source_group_bar.dart';
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
    // "正在读"页也读 ondeck：刷新书架时顺手让它重新取（两页共享同一份数据）；
    // 同时失效已缓存的系列详情与分卷列表，避免服务端新增卷后进详情页还看到旧缓存。
    ref.invalidate(ondeckProvider);
    ref.invalidate(seriesDetailProvider);
    ref.invalidate(seriesBooksProvider);
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
  WindowSizeClass _sizeClass(BuildContext context) =>
      WindowSizeClass.of(MediaQuery.sizeOf(context).width);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final motion = AppMotion.of(context);
    final sizeClass = _sizeClass(context);
    final state = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);
    final selection = ref.watch(shelfSelectionProvider);
    final selecting = ref.read(shelfSelectionProvider.notifier);
    final activeSource = ref.watch(activeSourceProvider);
    final isLocalShelf = activeSource.capabilities.canImportLocalFiles;
    final browseMode = isLocalShelf
        ? ref.watch(localShelfBrowseModeProvider)
        : LocalShelfBrowseMode.series;
    final showFolderTree =
        isLocalShelf &&
        !selection.active &&
        browseMode == LocalShelfBrowseMode.folders &&
        state.series.isNotEmpty;
    final allSelected =
        state.series.isNotEmpty && selection.ids.length == state.series.length;

    return Scaffold(
      body: Row(
        children: <Widget>[
          // 平板（≥1024）才显示左侧库导航（PLT-01）：手机上它会挤掉两列封面。
          if (sizeClass == WindowSizeClass.expanded) const ShelfSideRail(),
          Expanded(
            child: GlassPageBackground(
              child: Stack(
                children: <Widget>[
                  RefreshIndicator(
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
                            // 顶部常驻液态玻璃栏：常态为搜索框 + 管理圆球 + 三格工具胶囊；
                            // 进入管理书籍后原地形变为「管理书籍」+ 退出圆球 + 全标已读/未读/收藏集。
                            GlassHeaderSliver(
                              header: GlassHeader(
                                bar: ShelfHeaderBar(
                                  selecting: selection.active,
                                  selectedCount: selection.ids.length,
                                  batchBusy: _batchBusy,
                                  searchController: _searchController,
                                  onSearchChanged: controller.search,
                                  onEnterSelection: selecting.enter,
                                  onExitSelection: selecting.exit,
                                  onMarkRead: () => _markSelected(read: true),
                                  onMarkUnread: () =>
                                      _markSelected(read: false),
                                  onAddToCollection: _addSelectedToCollection,
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: SourceGroupBar(
                                showLocalImport:
                                    isLocalShelf &&
                                    !selection.active &&
                                    state.series.isNotEmpty,
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: LocalImportProgressBanner(),
                            ),
                            // 多选态紧凑信息行：常态不占高度，直接展示书架内容；
                            // 进入管理模式后平滑展开已选数量与全选动作（墨水屏直接瞬切）。
                            SliverToBoxAdapter(
                              child: _SelectionInfoRow(
                                active: selection.active,
                                selectedCount: selection.ids.length,
                                allSelected: allSelected,
                                motion: motion,
                                onSelectAll: () => selecting.selectAll(
                                  state.series.map((Series s) => s.id),
                                ),
                                onMergeSelected:
                                    isLocalShelf && selection.ids.length >= 2
                                    ? () => _mergeSelectedLocal(state.series)
                                    : null,
                                onDeleteSelected:
                                    isLocalShelf && selection.ids.isNotEmpty
                                    ? _deleteSelectedLocal
                                    : null,
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
                              phase: showFolderTree
                                  ? 'folders'
                                  : _phaseOf(state),
                              slivers: <Widget>[
                                if (showFolderTree)
                                  LocalFolderTreeSliver(query: state.query)
                                else
                                  ..._shelfSlivers(
                                    l10n,
                                    state,
                                    controller,
                                    isRealLocalShelf: isLocalShelf,
                                  ),
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
                  if (activeSource.capabilities.showsNetworkOfflineBanner)
                    OfflineOverlay(onRetry: () => unawaited(_refresh())),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
