part of 'library_screen.dart';

/// 书架的多选批量操作（LIB-03）。
///
/// 拆成 part + mixin：这块逻辑与"页面怎么排"无关，只是"对选中的系列做一件事"，
/// 页面本身也需要留出行数给布局。
mixin _ShelfBatch on ConsumerState<LibraryScreen> {
  /// 批量条正在提交（避免连点）。
  bool _batchBusy = false;

  /// 对选中的系列批量标记已读/未读（LIB-03）。
  ///
  /// 逐个发请求而不是批量端点：Komga 的"整系列已读"本身就是按系列调的，
  /// 没有跨系列的批量接口；失败项不中断其余项，最后统一提示一次。
  Future<void> _markSelected({required bool read}) async {
    final ids = ref.read(shelfSelectionProvider).ids.toList();
    if (ids.isEmpty || _batchBusy) return;
    final sourceKey = ref.read(activeSourceProvider).sourceKey;
    setState(() => _batchBusy = true);
    final reader = ref.read(seriesReadProvider.notifier);
    var failed = 0;
    for (final id in ids) {
      try {
        await reader.setRead(id, read: read, sourceKey: sourceKey);
      } on ShelfFailure {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _batchBusy = false);
    ref.read(shelfSelectionProvider.notifier).exit();
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? (read
                      ? l10n.batchMarkedRead(ids.length)
                      : l10n.batchMarkedUnread(ids.length))
                : l10n.batchPartialDone(ids.length - failed, failed),
          ),
        ),
      );
  }

  /// 对选中的系列批量加入收藏集。
  Future<void> _addSelectedToCollection() async {
    final ids = ref.read(shelfSelectionProvider).ids.toList();
    if (ids.isEmpty || _batchBusy) return;
    final sourceKey = ref.read(activeSourceProvider).sourceKey;
    final changed = await showCollectionPickerSheet(
      context,
      seriesIds: ids,
      sourceKey: sourceKey,
    );
    if (changed && mounted) {
      ref.read(shelfSelectionProvider.notifier).exit();
    }
  }

  Future<void> _mergeSelectedLocal(List<Series> shelfSeries) async {
    final ids = ref.read(shelfSelectionProvider).ids.toList();
    if (ids.length < 2 || _batchBusy) return;
    String defaultTitle = '';
    for (final s in shelfSeries) {
      if (s.id == ids.first) {
        defaultTitle = s.title;
        break;
      }
    }
    final merged = await showMergeLocalSeriesDialog(
      context,
      ref,
      selectedIds: ids,
      defaultTitle: defaultTitle,
    );
    if (merged && mounted) {
      ref.read(shelfSelectionProvider.notifier).exit();
    }
  }

  Future<void> _deleteSelectedLocal() async {
    final ids = ref.read(shelfSelectionProvider).ids.toList();
    if (ids.isEmpty || _batchBusy) return;
    final confirmed = await confirmDeleteLocalItems(context, count: ids.length);
    if (!confirmed || !mounted) return;
    setState(() => _batchBusy = true);
    try {
      await ref.read(localCatalogMutatorProvider).deleteSeries(ids);
      if (mounted) {
        ref.read(shelfSelectionProvider.notifier).exit();
      }
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }
}

/// 多选态紧凑信息行：常态不占高度，进入管理模式后展开已选数量与全选动作。
class _SelectionInfoRow extends StatelessWidget {
  const _SelectionInfoRow({
    required this.active,
    required this.selectedCount,
    required this.allSelected,
    required this.motion,
    required this.onSelectAll,
    this.onMergeSelected,
    this.onDeleteSelected,
  });

  final bool active;
  final int selectedCount;
  final bool allSelected;
  final AppMotion motion;
  final VoidCallback onSelectAll;
  final VoidCallback? onMergeSelected;
  final VoidCallback? onDeleteSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final content = active
        ? Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.selectedCount(selectedCount),
                    key: const Key('shelf-selection-count'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontFeatures: AppTypography.tabularFigures,
                    ),
                  ),
                ),
                if (onMergeSelected != null)
                  TextButton.icon(
                    key: const Key('shelf-selection-merge'),
                    style: TextButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                    ),
                    onPressed: onMergeSelected,
                    icon: const Icon(Icons.merge_type, size: AppSizes.iconXs),
                    label: Text(l10n.mergeIntoSeries),
                  ),
                if (onDeleteSelected != null)
                  TextButton.icon(
                    key: const Key('shelf-selection-delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                    ),
                    onPressed: onDeleteSelected,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: AppSizes.iconXs,
                    ),
                    label: Text(l10n.deleteFromDevice),
                  ),
                TextButton(
                  key: const Key('shelf-selection-all'),
                  style: TextButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                  ),
                  onPressed: allSelected ? null : onSelectAll,
                  child: Text(l10n.selectAll),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    // 墨水屏（motion.enabled == false）下直接瞬切，避免 AnimatedSize(Duration.zero)
    // 在 performLayout 中同步触发 markNeedsLayout 断言。
    if (!motion.enabled) return content;
    return AnimatedSize(
      duration: motion.quick,
      curve: motion.standardCurve,
      alignment: Alignment.topCenter,
      child: content,
    );
  }
}
