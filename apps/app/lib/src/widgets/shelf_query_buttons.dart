import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_view_options.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 排序选项的界面文案。
String _sortLabel(AppLocalizations l10n, SeriesSort sort) => switch (sort) {
  SeriesSort.titleAsc => l10n.sortTitleAsc,
  SeriesSort.titleDesc => l10n.sortTitleDesc,
  SeriesSort.recentlyAdded => l10n.sortRecentlyAdded,
  SeriesSort.recentlyRead => l10n.sortRecentlyRead,
  SeriesSort.booksCountDesc => l10n.sortBooksCount,
  SeriesSort.releaseDateDesc => l10n.sortReleaseDate,
};

/// 阅读状态筛选的界面文案。
String _readStatusLabel(AppLocalizations l10n, SeriesReadStatus status) =>
    switch (status) {
      SeriesReadStatus.unread => l10n.statusUnread,
      SeriesReadStatus.inProgress => l10n.statusInProgress,
      SeriesReadStatus.read => l10n.statusRead,
    };

/// 菜单项左侧的对勾占位：选中项打勾，未选中留同宽空位，文字不左右跳。
Widget _check(bool selected) => selected
    ? const Icon(Icons.check, size: AppSizes.iconXs)
    : const SizedBox(width: AppSizes.iconXs);

/// 书架排序按钮。
///
/// 用 [GlassMenuButton]（`MenuAnchor`）而不是 `PopupMenuButton`：触发器是标题栏
/// 玻璃胶囊里的一格，菜单是圆角浮层；值直接传枚举，不再需要 `String` + 空串
/// 绕开"`PopupMenuButton` 对 null 值不回调"的坑（踩过）。
class ShelfSortButton extends ConsumerWidget {
  const ShelfSortButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sort = ref.watch(shelfProvider.select((ShelfState s) => s.sort));
    final controller = ref.read(shelfProvider.notifier);
    return GlassMenuButton(
      key: const Key('shelf-sort-menu'),
      icon: Icons.sort,
      label: l10n.shelfSortTooltip,
      // 非默认排序时给一格选中底：不让"改过排序"只藏在下拉里。
      selected: sort != null,
      menuChildren: <Widget>[
        MenuItemButton(
          key: const Key('shelf-sort-default'),
          onPressed: () => controller.setSort(null),
          leadingIcon: _check(sort == null),
          child: Text(l10n.defaultOrder),
        ),
        for (final option in SeriesSort.values)
          MenuItemButton(
            key: Key('shelf-sort-${option.name}'),
            onPressed: () => controller.setSort(option),
            leadingIcon: _check(sort == option),
            child: Text(_sortLabel(l10n, option)),
          ),
      ],
    );
  }
}

/// 书架视图按钮（UI-P2-7）：网格 / 列表，以及封面小、中、大三档。
class ShelfViewButton extends ConsumerWidget {
  const ShelfViewButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);
    return GlassMenuButton(
      key: const Key('shelf-view-menu'),
      icon: state.view == ShelfView.grid ? Icons.grid_view : Icons.view_list,
      label: l10n.shelfViewTooltip,
      menuChildren: <Widget>[
        MenuItemButton(
          key: const Key('shelf-view-grid'),
          onPressed: () => controller.setView(ShelfView.grid),
          leadingIcon: _check(state.view == ShelfView.grid),
          child: Text(l10n.viewGrid),
        ),
        MenuItemButton(
          key: const Key('shelf-view-list'),
          onPressed: () => controller.setView(ShelfView.list),
          leadingIcon: _check(state.view == ShelfView.list),
          child: Text(l10n.viewList),
        ),
        const Divider(height: AppSizes.hairline),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            l10n.coverSize,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final size in ShelfCoverSize.values)
          MenuItemButton(
            key: Key('shelf-cover-${size.name}'),
            onPressed: () => controller.setCoverSize(size),
            leadingIcon: _check(state.coverSize == size),
            child: Text(switch (size) {
              ShelfCoverSize.small => l10n.coverSmall,
              ShelfCoverSize.medium => l10n.coverMedium,
              ShelfCoverSize.large => l10n.coverLarge,
            }),
          ),
      ],
    );
  }
}

/// 阅读状态筛选按钮（全部 / 未读 / 在读 / 已读）。
class ShelfFilterButton extends ConsumerWidget {
  const ShelfFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(
      shelfProvider.select((ShelfState s) => s.readStatus),
    );
    final controller = ref.read(shelfProvider.notifier);
    return GlassMenuButton(
      key: const Key('shelf-filter-menu'),
      icon: Icons.filter_list,
      label: l10n.shelfFilterTooltip,
      selected: status != null,
      menuChildren: <Widget>[
        MenuItemButton(
          key: const Key('shelf-filter-all'),
          onPressed: () => controller.setReadStatus(null),
          leadingIcon: _check(status == null),
          child: Text(l10n.all),
        ),
        for (final option in SeriesReadStatus.values)
          MenuItemButton(
            key: Key('shelf-filter-${option.name}'),
            onPressed: () => controller.setReadStatus(option),
            leadingIcon: _check(status == option),
            child: Text(_readStatusLabel(l10n, option)),
          ),
      ],
    );
  }
}
