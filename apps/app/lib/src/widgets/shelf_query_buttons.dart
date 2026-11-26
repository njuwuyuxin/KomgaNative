import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_view_options.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 排序选项的界面文案。
String _sortLabel(AppLocalizations l10n, SeriesSort sort) => switch (sort) {
  SeriesSort.titleAsc => l10n.sortTitleAsc,
  SeriesSort.titleDesc => l10n.sortTitleDesc,
  SeriesSort.recentlyAdded => l10n.sortRecentlyAdded,

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
/// 用 [GlassMenuButton]（`MenuAnchor`）而不是 `PopupMenuButton`：触发器是标题栏
/// 玻璃胶囊里的一格，菜单是玻璃浮层；值直接传枚举，不再需要 `String` + 空串
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
        GlassMenuItemButton(
          key: const Key('shelf-sort-default'),
          label: l10n.defaultOrder,
          checked: sort == null,
          onPressed: () => controller.setSort(null),
        ),
        for (final option in SeriesSort.values)
          GlassMenuItemButton(
            key: Key('shelf-sort-${option.name}'),
            label: _sortLabel(l10n, option),
            checked: sort == option,
            onPressed: () => controller.setSort(option),
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
        GlassMenuItemButton(
          key: const Key('shelf-view-grid'),
          label: l10n.viewGrid,
          checked: state.view == ShelfView.grid,
          onPressed: () => controller.setView(ShelfView.grid),
        ),
        GlassMenuItemButton(
          key: const Key('shelf-view-list'),
          label: l10n.viewList,
          checked: state.view == ShelfView.list,
          onPressed: () => controller.setView(ShelfView.list),
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
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final size in ShelfCoverSize.values)
          GlassMenuItemButton(
            key: Key('shelf-cover-${size.name}'),
            label: switch (size) {
              ShelfCoverSize.small => l10n.coverSmall,
              ShelfCoverSize.medium => l10n.coverMedium,
              ShelfCoverSize.large => l10n.coverLarge,
            },
            checked: state.coverSize == size,
            onPressed: () => controller.setCoverSize(size),
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
    final presets = ref.watch(
      shelfProvider.select((ShelfState s) => s.presets),
    );
    final hasFilter = ref.watch(
      shelfProvider.select(
        (ShelfState s) =>
            s.sort != null || s.readStatus != null || s.libraryId != null,
      ),
    );
    final controller = ref.read(shelfProvider.notifier);
    return GlassMenuButton(
      key: const Key('shelf-filter-menu'),
      icon: Icons.filter_list,
      label: l10n.shelfFilterTooltip,
      selected: status != null,
      menuChildren: <Widget>[
        GlassMenuItemButton(
          key: const Key('shelf-filter-all'),
          label: l10n.all,
          checked: status == null,
          onPressed: () => controller.setReadStatus(null),
        ),
        for (final option in SeriesReadStatus.values)
          GlassMenuItemButton(
            key: Key('shelf-filter-${option.name}'),
            label: _readStatusLabel(l10n, option),
            checked: status == option,
            onPressed: () => controller.setReadStatus(option),
          ),
        // 保存的筛选组合（LIB-04）：应用 / 删除。
        if (presets.isNotEmpty) ...<Widget>[
          const Divider(height: AppSizes.hairline),
          for (final preset in presets) ...<Widget>[
            GlassMenuItemButton(
              key: Key('shelf-preset-${preset.id}'),
              label: preset.name,
              onPressed: () => controller.applyPreset(preset),
            ),
            GlassMenuItemButton(
              key: Key('shelf-preset-delete-${preset.id}'),
              label: l10n.deletePresetNamed(preset.name),
              icon: Icons.delete_outline,
              onPressed: () => controller.deletePreset(preset.id),
            ),
          ],
        ],
        const Divider(height: AppSizes.hairline),
        GlassMenuItemButton(
          key: const Key('shelf-filter-save'),
          label: l10n.saveCurrentFilter,
          icon: Icons.bookmark_add_outlined,
          enabled: hasFilter,
          onPressed: () => unawaited(_promptPresetName(context, ref, l10n)),
        ),
      ],
    );
  }

  /// 弹一个输入框问名字，然后保存当前筛选组合。
  static Future<void> _promptPresetName(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final controller = ref.read(shelfProvider.notifier);
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _PresetNameDialog(
        title: l10n.filterPresetName,
        initial: l10n.filterPresetDefaultName(
          ref.read(shelfProvider).presets.length + 1,
        ),
        fieldKey: const Key('shelf-preset-name-field'),
        confirmKey: const Key('shelf-preset-save-confirm'),
        cancelLabel: l10n.cancel,
        saveLabel: l10n.save,
      ),
    );
    if (name != null) controller.savePreset(name);
  }
}

/// 命名对话框。
///
/// 控制器必须由这个 StatefulWidget 自己持有：在 showDialog 返回后立刻 dispose
/// 会在退场动画里被 TextField 再次使用（"used after being disposed"，踩过）。
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({
    required this.title,
    required this.initial,
    required this.fieldKey,
    required this.confirmKey,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final String title;
  final String initial;
  final Key fieldKey;
  final Key confirmKey;
  final String cancelLabel;
  final String saveLabel;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: widget.fieldKey,
        controller: _text,
        autofocus: true,
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          key: widget.confirmKey,
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
