import 'dart:async';

import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// 多选状态下钉在顶部的那一条（LIB-03）。
///
/// 换掉搜索框而不是叠在它上面：多选时搜索没有意义，留着只会让人误以为还能搜。
class ShelfSelectionBar extends StatelessWidget {
  const ShelfSelectionBar({
    required this.count,
    required this.total,
    required this.allSelected,
    required this.onSelectAll,
    required this.onClose,
    super.key,
  });

  final int count;
  final int total;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      key: const Key('shelf-selection-bar'),
      children: <Widget>[
        IconButton(
          key: const Key('shelf-selection-close'),
          tooltip: l10n.cancel,
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
        Expanded(
          child: Text(
            l10n.selectedCount(count),
            key: const Key('shelf-selection-count'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
        ),
        TextButton(
          key: const Key('shelf-selection-all'),
          onPressed: allSelected ? null : onSelectAll,
          child: Text(l10n.selectAll),
        ),
      ],
    );
  }
}

/// 多选时的底部批量条。
///
/// 只放"一次能对一整个系列做完"的动作。下载没接（等 SER-03 的系列下载链），
/// 先不摆一个按了没反应的按钮。
class ShelfBatchBar extends StatelessWidget {
  const ShelfBatchBar({
    required this.count,
    required this.busy,
    required this.onMarkRead,
    required this.onMarkUnread,
    super.key,
  });

  final int count;
  final bool busy;
  final Future<void> Function() onMarkRead;
  final Future<void> Function() onMarkUnread;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GlassSurface(
      key: const Key('shelf-batch-bar'),
      shape: AppShapes.of(context, AppShapes.bar),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextButton.icon(
                key: const Key('shelf-batch-read'),
                onPressed: busy ? null : () => unawaited(onMarkRead()),
                icon: const Icon(Icons.done_all, size: AppSizes.iconSm),
                label: Text(l10n.markAllRead, maxLines: 1),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                key: const Key('shelf-batch-unread'),
                onPressed: busy ? null : () => unawaited(onMarkUnread()),
                icon: const Icon(Icons.remove_done, size: AppSizes.iconSm),
                label: Text(l10n.markAllUnread, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
