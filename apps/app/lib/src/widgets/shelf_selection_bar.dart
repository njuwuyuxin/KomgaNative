import 'dart:async';

import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
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

/// 多选时的底部悬浮批量条：支持标记已读/未读，以及可选的第三项（加入收藏集 / 加入阅读列表）。
///
/// 与底部导航条（`FloatingNavBar`）同一套液态玻璃胶囊形态：图标在上、标签在下，
/// 按下轻微缩放与触感反馈；墨水屏由 token 自动退化为纸底墨框。
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
      child: Row(
        children: <Widget>[
          Expanded(
            child: _BatchAction(
              key: const Key('shelf-batch-read'),
              icon: Icons.done_all,
              label: l10n.markAllRead,
              onPressed: disabled ? null : () => unawaited(onMarkRead()),
            ),
          ),
          Expanded(
            child: _BatchAction(
              key: const Key('shelf-batch-unread'),
              icon: Icons.remove_done,
              label: l10n.markAllUnread,
              onPressed: disabled ? null : () => unawaited(onMarkUnread()),
            ),
          ),
          if (hasExtra)
            Expanded(
              child: _BatchAction(
                key: extraKey,
                icon: extraIcon!,
                label: extraLabel!,
                onPressed: disabled ? null : () => unawaited(onExtraAction!()),
              ),
            ),
        ],
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final baseColor = GlassControlColors.resolve(context).foreground;
    final foreground = enabled ? baseColor : baseColor.withValues(alpha: 0.38);

    void handleTap() {
      final callback = onPressed;
      if (callback == null) return;
      unawaited(AppHaptics.selection());
      callback();
    }

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: enabled ? handleTap : null,
      child: ExcludeSemantics(
        child: PressableScale(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? handleTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppSizes.navBarHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(icon, size: AppSizes.iconLg, color: foreground),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.of(context).label
                          .copyWith(color: foreground),
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
}
