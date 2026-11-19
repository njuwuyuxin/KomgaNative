import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/widgets/shelf_selection_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 系列内书列表的工具条（SER-01）：总数 + 排序 + 阅读状态筛选。
///
/// 只放**已验证**的排序项：`metadata.numberSort,asc|desc`。
/// "添加时间 / 发行日期"在真实库上无法与默认顺序区分，按 API 真值规则暂不上线
/// （见 `docs/series-queries.md` 的 LIB-04 复验一节，判定方法与结论都在那里）。
class SeriesBooksToolbar extends StatelessWidget {
  const SeriesBooksToolbar({
    required this.total,
    required this.sort,
    required this.readStatus,
    required this.onSort,
    required this.onReadStatus,
    this.selecting = false,
    this.selectedCount = 0,
    this.allSelected = false,
    this.onEnterSelection,
    this.onExitSelection,
    this.onSelectAll,
    super.key,
  });

  final int total;
  final BooksSort? sort;
  final SeriesReadStatus? readStatus;
  final ValueChanged<BooksSort?> onSort;
  final ValueChanged<SeriesReadStatus?> onReadStatus;

  /// 多选态（SER-02）：进入后这一行换成"已选 N / 全选 / 取消"。
  final bool selecting;
  final int selectedCount;
  final bool allSelected;
  final VoidCallback? onEnterSelection;
  final VoidCallback? onExitSelection;
  final VoidCallback? onSelectAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final filtered = sort != null || readStatus != null;

    if (selecting) {
      return ShelfSelectionBar(
        count: selectedCount,
        total: total,
        allSelected: allSelected,
        onSelectAll: onSelectAll ?? () {},
        onClose: onExitSelection ?? () {},
        countLabel: l10n.booksSelected,
      );
    }

    return Padding(
      key: const Key('series-books-toolbar'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: Row(
        children: <Widget>[
          Text(
            // 有筛选时"总数"会误导：这里显示的是**筛选后**的条数。
            // 服务端会按筛选返回 totalElements，所以两者天然一致。
            l10n.booksCount(total),
            key: const Key('series-books-count'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          GlassMenuButton(
            key: const Key('series-books-sort'),
            icon: Icons.sort,
            label: l10n.shelfSortTooltip,
            selected: sort != null,
            menuChildren: <Widget>[
              GlassMenuItemButton(
                key: const Key('series-sort-default'),
                label: l10n.defaultOrder,
                checked: sort == null,
                onPressed: () => onSort(null),
              ),
              GlassMenuItemButton(
                key: const Key('series-sort-number-asc'),
                label: l10n.sortVolumeAsc,
                checked: sort == BooksSort.numberAsc,
                onPressed: () => onSort(BooksSort.numberAsc),
              ),
              GlassMenuItemButton(
                key: const Key('series-sort-number-desc'),
                label: l10n.sortVolumeDesc,
                checked: sort == BooksSort.numberDesc,
                onPressed: () => onSort(BooksSort.numberDesc),
              ),
            ],
          ),
          GlassMenuButton(
            key: const Key('series-books-filter'),
            icon: Icons.filter_list,
            label: l10n.shelfFilterTooltip,
            selected: readStatus != null,
            menuChildren: <Widget>[
              GlassMenuItemButton(
                key: const Key('series-filter-all'),
                label: l10n.all,
                checked: readStatus == null,
                onPressed: () => onReadStatus(null),
              ),
              for (final status in SeriesReadStatus.values)
                GlassMenuItemButton(
                  key: Key('series-filter-${status.name}'),
                  label: switch (status) {
                    SeriesReadStatus.unread => l10n.statusUnread,
                    SeriesReadStatus.inProgress => l10n.statusInProgress,
                    SeriesReadStatus.read => l10n.statusRead,
                  },
                  checked: readStatus == status,
                  onPressed: () => onReadStatus(status),
                ),
            ],
          ),
          if (filtered)
            IconButton(
              key: const Key('series-books-clear'),
              tooltip: l10n.clearFilters,
              onPressed: () {
                onSort(null);
                onReadStatus(null);
              },
              icon: const Icon(Icons.close),
            ),
          if (onEnterSelection != null)
            IconButton(
              key: const Key('series-books-select'),
              tooltip: l10n.selectSeries,
              onPressed: onEnterSelection,
              icon: const Icon(Icons.checklist),
            ),
        ],
      ),
    );
  }
}
