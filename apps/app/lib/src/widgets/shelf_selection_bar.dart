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
    this.countLabel,
    super.key,
  });

  final int count;
  final int total;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClose;

  /// "已选 N"的文案；默认按"个"（书架），系列页传"本"。
  final String Function(int count)? countLabel;

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
            countLabel?.call(count) ?? l10n.selectedCount(count),
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

/// 多选时的底部批量条：支持标记已读/未读，以及可选的第三项（加入收藏集 / 加入阅读列表）。
class ShelfBatchBar extends StatelessWidget {
  const ShelfBatchBar({
    required this.count,
    required this.busy,
    required this.onMarkRead,
    required this.onMarkUnread,
    this.extraLabel,
    this.extraIcon,
    this.extraKey,
    this.onExtraAction,
    super.key,
  });

  final int count;
  final bool busy;
  final Future<void> Function() onMarkRead;
  final Future<void> Function() onMarkUnread;
  final String? extraLabel;
  final IconData? extraIcon;
  final Key? extraKey;
  final Future<void> Function()? onExtraAction;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final disabled = busy || count == 0;
    final hasExtra =
        onExtraAction != null && extraLabel != null && extraIcon != null;

    return GlassSurface(
      key: const Key('shelf-batch-bar'),
      shape: AppShapes.of(context, AppShapes.bar),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _BatchAction(
                key: const Key('shelf-batch-read'),
                icon: Icons.done_all,
                label: l10n.markAllRead,
                stacked: hasExtra,
                onPressed: disabled ? null : () => unawaited(onMarkRead()),
              ),
            ),
            Expanded(
              child: _BatchAction(
                key: const Key('shelf-batch-unread'),
                icon: Icons.remove_done,
                label: l10n.markAllUnread,
                stacked: hasExtra,
                onPressed: disabled ? null : () => unawaited(onMarkUnread()),
              ),
            ),
            if (hasExtra)
              Expanded(
                child: _BatchAction(
                  key: extraKey,
                  icon: extraIcon!,
                  label: extraLabel!,
                  stacked: true,
                  onPressed: disabled
                      ? null
                      : () => unawaited(onExtraAction!()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.stacked,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool stacked;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (!stacked) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: AppSizes.iconSm),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
    }
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: AppSizes.iconSm),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
