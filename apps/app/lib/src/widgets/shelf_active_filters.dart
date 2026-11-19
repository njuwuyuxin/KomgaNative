import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 书架生效中的筛选条件（LIB-01）。
///
/// 为什么要有这一条：排序/阅读状态/库筛选都藏在三个图标的下拉里，
/// 用户看到的是"书架少了一堆书"却不知道是哪一项在起作用。
/// 这里把**当前生效**的条件摊成可单独清除的 chips，最后给一个"清除全部"。
class ShelfActiveFilters extends ConsumerWidget {
  const ShelfActiveFilters({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);
    final chips = <Widget>[
      if (state.sort != null)
        _FilterChip(
          key: const Key('shelf-chip-sort'),
          label: _sortLabel(l10n, state.sort!),
          onClear: () => controller.setSort(null),
        ),
      if (state.readStatus != null)
        _FilterChip(
          key: const Key('shelf-chip-status'),
          label: _statusLabel(l10n, state.readStatus!),
          onClear: () => controller.setReadStatus(null),
        ),
      if (state.libraryId != null)
        _FilterChip(
          key: const Key('shelf-chip-library'),
          label:
              ref
                  .watch(librariesProvider)
                  .value
                  ?.where((Library lib) => lib.id == state.libraryId)
                  .map((Library lib) => lib.name)
                  .firstOrNull ??
              l10n.libraryFilterTitle,
          onClear: () => controller.selectLibrary(null),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      key: const Key('shelf-active-filters'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        0,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            ...chips,
            if (chips.length > 1)
              TextButton(
                key: const Key('shelf-clear-filters'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, AppSizes.minTouch),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                onPressed: () {
                  controller.setSort(null);
                  controller.setReadStatus(null);
                  controller.selectLibrary(null);
                },
                child: Text(l10n.clearFilters),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一个可清除的条件 chip。
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onClear, super.key});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: GlassSurface(
        shape: AppShapes.of(context, AppShapes.bar),
        child: InkWell(
          onTap: onClear,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.close,
                  size: AppSizes.iconXs,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _sortLabel(AppLocalizations l10n, SeriesSort sort) => switch (sort) {
  SeriesSort.titleAsc => l10n.sortTitleAsc,
  SeriesSort.titleDesc => l10n.sortTitleDesc,
  SeriesSort.recentlyAdded => l10n.sortRecentlyAdded,
  SeriesSort.booksCountDesc => l10n.sortBooksCount,
  SeriesSort.releaseDateDesc => l10n.sortReleaseDate,
};

String _statusLabel(AppLocalizations l10n, SeriesReadStatus status) =>
    switch (status) {
      SeriesReadStatus.unread => l10n.statusUnread,
      SeriesReadStatus.inProgress => l10n.statusInProgress,
      SeriesReadStatus.read => l10n.statusRead,
    };
