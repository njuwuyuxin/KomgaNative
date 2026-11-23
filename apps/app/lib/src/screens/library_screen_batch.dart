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
    setState(() => _batchBusy = true);
    final reader = ref.read(seriesReadProvider.notifier);
    var failed = 0;
    for (final id in ids) {
      try {
        await reader.setRead(id, read: read);
      } on ShelfFailure {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _batchBusy = false);
    ref.read(shelfSelectionProvider.notifier).exit();
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? l10n.batchDone(ids.length)
              : l10n.batchPartialDone(ids.length - failed, failed),
        ),
      ),
    );
  }

  /// 对选中的系列批量加入收藏集。
  Future<void> _addSelectedToCollection() async {
    final ids = ref.read(shelfSelectionProvider).ids.toList();
    if (ids.isEmpty || _batchBusy) return;
    final changed = await showCollectionPickerSheet(context, seriesIds: ids);
    if (changed && mounted) {
      ref.read(shelfSelectionProvider.notifier).exit();
    }
  }
}
