import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/curation_ops.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/collections_controller.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/curation_detail_rows.dart';
import 'package:yomu/src/widgets/curation_dialogs.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读列表里的书（UI-P3-8 / ARC-12 增量分页 + 完整移出/编辑/删除管理）。
class ReadListDetailScreen extends ConsumerStatefulWidget {
  const ReadListDetailScreen({required this.readListId, this.title, super.key});

  final String readListId;
  final String? title;

  @override
  ConsumerState<ReadListDetailScreen> createState() =>
      _ReadListDetailScreenState();
}

class _ReadListDetailScreenState extends ConsumerState<ReadListDetailScreen> {
  final Set<String> _hiddenIds = <String>{};

  String _displayTitle(AppLocalizations l10n, ReadList? detail) =>
      detail?.name ?? widget.title ?? l10n.readListFallback;

  List<String> _currentBookIds(ReadList? detail, PageResult<Book>? page) {
    if (detail != null && detail.bookIds.isNotEmpty) return detail.bookIds;
    return <String>[for (final b in page?.items ?? const <Book>[]) b.id];
  }

  Future<void> _editReadList(ReadList? detail, String currentName) async {
    final l10n = AppLocalizations.of(context);
    final form = await promptReadListForm(
      context,
      title: l10n.readListEdit,
      initialName: detail?.name ?? currentName,
      initialSummary: detail?.summary ?? '',
    );
    if (form == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .updateReadList(
            widget.readListId,
            name: form.name,
            summary: form.summary,
          );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.readListSaved)));
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<void> _deleteReadList(String currentName) async {
    final confirmed = await confirmReadListDelete(context, currentName);
    if (!confirmed || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .deleteReadList(widget.readListId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.readListSaved)));
      if (GoRouter.maybeOf(context)?.canPop() ?? false) context.pop();
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<bool> _removeBook(
    Book book, {
    required String displayName,
    required ReadList? detail,
    required PageResult<Book>? page,
    bool fromSwipe = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final currentIds = _currentBookIds(detail, page);
    final remaining = removeMatchingIds(currentIds, <String>[book.id]);
    final messenger = ScaffoldMessenger.of(context);

    if (remaining.isEmpty) {
      final confirmed = await confirmDestructiveCuration(
        context,
        title: l10n.readListRemoveLastTitle,
        body: l10n.readListRemoveLastBody(displayName),
        confirmLabel: l10n.delete,
        dialogKey: const Key('readlist-remove-last-confirm'),
        okKey: const Key('readlist-remove-last-ok'),
      );
      if (!confirmed || !mounted) return false;
      try {
        await ref
            .read(collectionsControllerProvider.notifier)
            .deleteReadList(widget.readListId);
        if (!mounted) return true;
        messenger.showSnackBar(SnackBar(content: Text(l10n.readListSaved)));
        if (GoRouter.maybeOf(context)?.canPop() ?? false) context.pop();
        return true;
      } on ShelfFailure catch (failure) {
        if (!mounted) return false;
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.failureTitle(failure.kind))),
        );
        return false;
      }
    }

    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .updateReadList(widget.readListId, bookIds: remaining);
      if (!mounted) return true;
      if (fromSwipe) setState(() => _hiddenIds.add(book.id));
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.readListRemoved(displayName)),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () => unawaited(_restoreBook(currentIds, book.id)),
          ),
        ),
      );
      return true;
    } on ShelfFailure catch (failure) {
      if (!mounted) return false;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
      return false;
    }
  }

  Future<void> _restoreBook(List<String> previousIds, String restoredId) async {
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .updateReadList(widget.readListId, bookIds: previousIds);
      if (mounted) setState(() => _hiddenIds.remove(restoredId));
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failureTitle(failure.kind))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = readListBooksProvider(widget.readListId);
    final async = ref.watch(provider);
    final detail = ref.watch(readListDetailProvider(widget.readListId)).value;
    final displayName = _displayTitle(l10n, detail);

    return Scaffold(
      body: GlassPageBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(
                leading: GlassIconButton(
                  icon: Icons.chevron_left,
                  label: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.pop(),
                ),
                title: Text(displayName),
                trailing: GlassMenuButton(
                  key: const Key('readlist-detail-menu'),
                  orb: true,
                  icon: Icons.more_horiz,
                  label: l10n.moreActions,
                  menuChildren: <Widget>[
                    GlassMenuItemButton(
                      key: const Key('readlist-detail-edit'),
                      label: l10n.readListEdit,
                      onPressed: () =>
                          unawaited(_editReadList(detail, displayName)),
                    ),
                    GlassMenuItemButton(
                      key: const Key('readlist-detail-delete'),
                      label: l10n.readListDelete,
                      onPressed: () => unawaited(_deleteReadList(displayName)),
                    ),
                  ],
                ),
              ),
            ),
            ReadListBooksSliver(
              async: async,
              hiddenIds: _hiddenIds,
              onRetry: () => ref.invalidate(provider),
              onLoadMore: () =>
                  unawaited(ref.read(provider.notifier).loadMore()),
              onAfterRead: () => ref.invalidate(provider),
              onRemove: (Book book, {bool fromSwipe = false}) => _removeBook(
                book,
                displayName: displayName,
                detail: detail,
                page: async.value,
                fromSwipe: fromSwipe,
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSizes.navBarClearance),
            ),
          ],
        ),
      ),
    );
  }
}
