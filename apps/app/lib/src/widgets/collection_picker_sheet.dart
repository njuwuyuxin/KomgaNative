import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/curation_ops.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/collections_controller.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/collection_covers.dart';
import 'package:yomu/src/widgets/curation_dialogs.dart';
import 'package:yomu/src/widgets/membership_picker_sheet.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 弹出「添加到收藏集」勾选面板，支持单个系列或批量多选系列。
///
/// 返回 `true` 表示服务端收藏集已发生更新。
Future<bool> showCollectionPickerSheet(
  BuildContext context, {
  required List<String> seriesIds,
  String? sourceKey,
}) async {
  if (seriesIds.isEmpty) return false;
  final resolvedSource = sourceKey ?? ScopedSourceScope.readOf(context);
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (BuildContext context) => ScopedSourceScope(
      sourceKey: resolvedSource,
      child: _CollectionPickerSheet(
        seriesIds: seriesIds,
        sourceKey: resolvedSource,
      ),
    ),
  );
  return changed == true;
}

class _CollectionPickerSheet extends ConsumerWidget {
  const _CollectionPickerSheet({required this.seriesIds, this.sourceKey});

  final List<String> seriesIds;
  final String? sourceKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final resolvedSource =
        sourceKey ?? ref.watch(activeSourceProvider).sourceKey;
    final async = ref.watch(allCollectionsForSourceProvider(resolvedSource));

    return MembershipPickerSheet<Collection>(
      asyncItems: async,
      targetIds: seriesIds,
      itemId: (Collection c) => c.id,
      itemName: (Collection c) => c.name,
      itemMemberIds: (Collection c) => c.seriesIds,
      sheetKey: const Key('collection-picker-sheet'),
      createButtonKey: const Key('collection-picker-create'),
      searchFieldKey: const Key('collection-picker-search'),
      saveButtonKey: const Key('collection-picker-save'),
      itemKeyPrefix: 'collection-pick-',
      emptyDeleteDialogKey: const Key('collection-empty-delete-confirm'),
      emptyDeleteOkKey: const Key('collection-empty-delete-ok'),
      title: l10n.addToCollection,
      createLabel: l10n.collectionCreate,
      searchHint: l10n.searchCollectionsHint,
      emptyIcon: Icons.collections_bookmark_outlined,
      emptyTitle: l10n.collectionsEmpty,
      emptyDeleteTitle: l10n.collectionEmptyDeleteTitle,
      emptyDeleteBody: l10n.collectionEmptyDeleteBody,
      savedMessage: (MembershipChangePlan plan) => plan.isPureAddition
          ? l10n.batchAddedToCollection(seriesIds.length)
          : l10n.collectionSaved,
      buildSecondary: (Collection c) => CollectionCovers(
        collectionId: c.id,
        name: c.name,
        seriesIds: c.seriesIds,
      ),
      buildSubtitle: (Collection c, MembershipState state, int hitCount) =>
          state == MembershipState.partial
          ? l10n.collectionsPartialMember(hitCount)
          : l10n.seriesCount(c.seriesCount),
      onRetry: () =>
          ref.invalidate(allCollectionsForSourceProvider(resolvedSource)),
      onCreate: (BuildContext dialogContext, VoidCallback markSaving) async {
        final name = await promptCollectionName(
          dialogContext,
          title: l10n.collectionCreate,
          dialogKey: const Key('collection-create-dialog'),
          fieldKey: const Key('collection-create-field'),
          okKey: const Key('collection-create-ok'),
        );
        if (!context.mounted || name == null || name.isEmpty) return null;
        markSaving();
        await ref
            .read(collectionsControllerProvider.notifier)
            .create(
              name: name,
              seriesIds: seriesIds,
              sourceKey: resolvedSource,
            );
        return l10n.batchAddedToCollection(seriesIds.length);
      },
      onApplyPlan: (MembershipChangePlan plan) => ref
          .read(collectionsControllerProvider.notifier)
          .applyCollectionPlan(
            plan,
            affectedSeriesIds: seriesIds,
            sourceKey: resolvedSource,
          ),
    );
  }
}
