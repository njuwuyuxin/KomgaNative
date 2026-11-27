import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/curation_ops.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/collections_controller.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/curation_dialogs.dart';
import 'package:yomu/src/widgets/membership_picker_sheet.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 弹出「添加到阅读列表」勾选面板，支持单本书或批量多选书。
///
/// 返回 `true` 表示服务端阅读列表已发生更新。
Future<bool> showReadListPickerSheet(
  BuildContext context, {
  required List<String> bookIds,
  String? sourceKey,
}) async {
  if (bookIds.isEmpty) return false;
  final resolvedSource = sourceKey ?? ScopedSourceScope.readOf(context);
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (BuildContext context) => ScopedSourceScope(
      sourceKey: resolvedSource,
      child: _ReadListPickerSheet(bookIds: bookIds, sourceKey: resolvedSource),
    ),
  );
  return changed == true;
}

class _ReadListPickerSheet extends ConsumerWidget {
  const _ReadListPickerSheet({required this.bookIds, this.sourceKey});

  final List<String> bookIds;
  final String? sourceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final resolvedSource =
        sourceKey ?? ref.watch(activeSourceProvider).sourceKey;
    final async = ref.watch(allReadListsForSourceProvider(resolvedSource));

    return MembershipPickerSheet<ReadList>(
      asyncItems: async,
      targetIds: bookIds,
      itemId: (ReadList list) => list.id,
      itemName: (ReadList list) => list.name,
      itemMemberIds: (ReadList list) => list.bookIds,
      sheetKey: const Key('readlist-picker-sheet'),
      createButtonKey: const Key('readlist-picker-create'),
      searchFieldKey: const Key('readlist-picker-search'),
      saveButtonKey: const Key('readlist-picker-save'),
      itemKeyPrefix: 'readlist-pick-',
      emptyDeleteDialogKey: const Key('readlist-empty-delete-confirm'),
      emptyDeleteOkKey: const Key('readlist-empty-delete-ok'),
      title: l10n.addToReadList,
      createLabel: l10n.readListCreate,
      searchHint: l10n.searchReadListsHint,
      emptyIcon: Icons.list_alt_outlined,
      emptyTitle: l10n.readListsEmpty,
      emptyDeleteTitle: l10n.readListEmptyDeleteTitle,
      emptyDeleteBody: l10n.readListEmptyDeleteBody,
      savedMessage: (MembershipChangePlan plan) => plan.isPureAddition
          ? l10n.batchAddedToReadList(bookIds.length)
          : l10n.readListSaved,
      buildSecondary: (_) => const Icon(Icons.list_alt_outlined),
      buildSubtitle: (ReadList list, MembershipState state, int hitCount) =>
          state == MembershipState.partial
          ? l10n.readListsPartialMember(hitCount)
          : list.summary.isEmpty
          ? l10n.bookCount(list.bookCount)
          : '${l10n.bookCount(list.bookCount)} · ${list.summary}',
      onRetry: () =>
          ref.invalidate(allReadListsForSourceProvider(resolvedSource)),
      onCreate: (BuildContext dialogContext, VoidCallback markSaving) async {
        final form = await promptReadListForm(
          dialogContext,
          title: l10n.readListCreate,
          dialogKey: const Key('readlist-create-dialog'),
          nameKey: const Key('readlist-create-name'),
          summaryKey: const Key('readlist-create-summary'),
          okKey: const Key('readlist-create-ok'),
        );
        if (!context.mounted || form == null) return null;
        markSaving();
        final created = await ref
            .read(collectionsControllerProvider.notifier)
            .createReadList(
              name: form.name,
              summary: form.summary,
              bookIds: bookIds,
              sourceKey: resolvedSource,
            );
        return l10n.readListAddedTo(created.name);
      },
      onApplyPlan: (MembershipChangePlan plan) => ref
          .read(collectionsControllerProvider.notifier)
          .applyReadListPlan(plan, sourceKey: resolvedSource),
    );
  }
}
