import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// 书架排序按钮。
///
/// 菜单值用 `String` 而不是可空枚举：`PopupMenuButton` 对 `null` 值不会回调
/// `onSelected`，"恢复默认顺序"这个选项就会失效（踩过）。空串代表"不指定"。
class ShelfSortButton extends ConsumerWidget {
  const ShelfSortButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sort = ref.watch(shelfProvider.select((ShelfState s) => s.sort));
    return PopupMenuButton<String>(
      key: const Key('shelf-sort-menu'),
      tooltip: l10n.shelfSortTooltip,
      icon: const Icon(Icons.sort),
      initialValue: sort?.name ?? '',
      onSelected: (String value) => ref
          .read(shelfProvider.notifier)
          .setSort(
            value.isEmpty
                ? null
                : SeriesSort.values.firstWhere(
                    (SeriesSort s) => s.name == value,
                  ),
          ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: '', child: Text(l10n.defaultOrder)),
        for (final option in SeriesSort.values)
          PopupMenuItem<String>(
            value: option.name,
            key: Key('shelf-sort-${option.name}'),
            child: Text(_sortLabel(l10n, option)),
          ),
      ],
    );
  }
}

/// 书架视图按钮（UI-P2-7）：网格 / 列表，以及封面小、中、大三档。
///
/// 菜单值用 `String`（`grid` / `list` / `size-*`）——`PopupMenuButton` 对 `null`
/// 值不回调 `onSelected`，混着两种枚举还会让 `initialValue` 失去意义。
class ShelfViewButton extends ConsumerWidget {
  const ShelfViewButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);
    return PopupMenuButton<String>(
      key: const Key('shelf-view-menu'),
      tooltip: l10n.shelfViewTooltip,
      icon: Icon(
        state.view == ShelfView.grid ? Icons.grid_view : Icons.view_list,
      ),
      onSelected: (String value) {
        if (value == 'grid') controller.setView(ShelfView.grid);
        if (value == 'list') controller.setView(ShelfView.list);
        for (final size in ShelfCoverSize.values) {
          if (value == 'size-${size.name}') controller.setCoverSize(size);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        CheckedPopupMenuItem<String>(
          key: const Key('shelf-view-grid'),
          value: 'grid',
          checked: state.view == ShelfView.grid,
          child: Text(l10n.viewGrid),
        ),
        CheckedPopupMenuItem<String>(
          key: const Key('shelf-view-list'),
          value: 'list',
          checked: state.view == ShelfView.list,
          child: Text(l10n.viewList),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          key: const Key('shelf-cover-size-header'),
          enabled: false,
          child: Text(l10n.coverSize),
        ),
        for (final size in ShelfCoverSize.values)
          CheckedPopupMenuItem<String>(
            key: Key('shelf-cover-${size.name}'),
            value: 'size-${size.name}',
            checked: state.coverSize == size,
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
    return PopupMenuButton<String>(
      key: const Key('shelf-filter-menu'),
      tooltip: l10n.shelfFilterTooltip,
      icon: const Icon(Icons.filter_list),
      initialValue: status?.name ?? '',
      onSelected: (String value) => ref
          .read(shelfProvider.notifier)
          .setReadStatus(
            value.isEmpty
                ? null
                : SeriesReadStatus.values.firstWhere(
                    (SeriesReadStatus s) => s.name == value,
                  ),
          ),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          key: const Key('shelf-filter-all'),
          value: '',
          child: Text(l10n.all),
        ),
        for (final option in SeriesReadStatus.values)
          PopupMenuItem<String>(
            key: Key('shelf-filter-${option.name}'),
            value: option.name,
            child: Text(_readStatusLabel(l10n, option)),
          ),
      ],
    );
  }
}
