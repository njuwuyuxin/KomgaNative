import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/curation_ops.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/collections_controller.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/widgets/collection_covers.dart';
import 'package:yomu/src/widgets/curation_dialogs.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:material_ui/material_ui.dart';

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

class _CollectionPickerSheet extends ConsumerStatefulWidget {
  const _CollectionPickerSheet({required this.seriesIds, this.sourceKey});

  final List<String> seriesIds;
  final String? sourceKey;

  @override
  ConsumerState<_CollectionPickerSheet> createState() =>
      _CollectionPickerSheetState();
}

class _CollectionPickerSheetState
    extends ConsumerState<_CollectionPickerSheet> {
  final Map<String, MembershipState> _desired = <String, MembershipState>{};
  String _query = '';
  bool _saving = false;

  bool get _isBatch => widget.seriesIds.length > 1;

  MembershipChangePlan _planFor(List<Collection> collections) =>
      planMembershipChanges(
        containers: <({String id, String name, List<String> memberIds})>[
          for (final c in collections)
            (id: c.id, name: c.name, memberIds: c.seriesIds),
        ],
        targetIds: widget.seriesIds,
        desiredStates: _desired,
      );

  void _toggle(Collection collection) {
    unawaited(AppHaptics.selection());
    final initial = membershipOf(collection.seriesIds, widget.seriesIds);
    final current = _desired[collection.id] ?? initial;
    final next = current == MembershipState.all
        ? MembershipState.none
        : MembershipState.all;
    setState(() {
      if (next == initial) {
        _desired.remove(collection.id);
      } else {
        _desired[collection.id] = next;
      }
    });
  }

  Future<void> _createNew(List<Collection> current) async {
    final l10n = AppLocalizations.of(context);
    final name = await promptCollectionName(
      context,
      title: l10n.collectionCreate,
      dialogKey: const Key('collection-create-dialog'),
      fieldKey: const Key('collection-create-field'),
      okKey: const Key('collection-create-ok'),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .create(
            name: name,
            seriesIds: widget.seriesIds,
            sourceKey: widget.sourceKey,
          );
      if (!mounted) return;
      final hasPendingEdits = !_planFor(current).isEmpty;
      final message = l10n.batchAddedToCollection(widget.seriesIds.length);
      if (!hasPendingEdits) {
        Navigator.of(context).pop(true);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      } else {
        setState(() => _saving = false);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<void> _save(List<Collection> collections) async {
    final plan = _planFor(collections);
    if (plan.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (plan.deletions.isNotEmpty) {
      final names = plan.deletions.map((d) => d.name).join('、');
      final ok = await confirmDestructiveCuration(
        context,
        title: l10n.collectionEmptyDeleteTitle,
        body: l10n.collectionEmptyDeleteBody(names),
        confirmLabel: l10n.delete,
        dialogKey: const Key('collection-empty-delete-confirm'),
        okKey: const Key('collection-empty-delete-ok'),
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .applyCollectionPlan(
            plan,
            affectedSeriesIds: widget.seriesIds,
            sourceKey: widget.sourceKey,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      final message = plan.isPureAddition
          ? l10n.batchAddedToCollection(widget.seriesIds.length)
          : l10n.collectionSaved;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sourceKey =
        widget.sourceKey ?? ref.watch(activeSourceProvider).sourceKey;
    final async = ref.watch(allCollectionsForSourceProvider(sourceKey));
    final items = async.value;
    final hasChanges = items != null && !_planFor(items).isEmpty;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return ConstrainedBox(
      key: const Key('collection-picker-sheet'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l10n.addToCollection,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('collection-picker-create'),
                    onPressed: _saving
                        ? null
                        : () => unawaited(
                            _createNew(items ?? const <Collection>[]),
                          ),
                    icon: const Icon(Icons.add, size: AppSizes.iconSm),
                    label: Text(l10n.collectionCreate),
                  ),
                ],
              ),
            ),
            if (items != null && items.length > 5)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: TextField(
                  key: const Key('collection-picker-search'),
                  onChanged: (String v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l10n.searchCollectionsHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
            Flexible(child: _buildBody(context, l10n, async, sourceKey)),
            const Divider(height: AppSizes.hairline),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('collection-picker-save'),
                  onPressed: _saving || items == null
                      ? null
                      : () => unawaited(_save(items)),
                  child: _saving
                      ? const SizedBox(
                          width: AppSizes.iconSm,
                          height: AppSizes.iconSm,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(hasChanges ? l10n.save : l10n.done),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<List<Collection>> async,
    String sourceKey,
  ) {
    if (async.hasError && !async.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: StatusView(
          icon: Icons.cloud_off_outlined,
          title: l10n.failureTitle(failureKindOf(async.error)),
          actionLabel: l10n.retry,
          onAction: () =>
              ref.invalidate(allCollectionsForSourceProvider(sourceKey)),
        ),
      );
    }
    final items = async.value;
    if (items == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: StatusView(
          icon: Icons.collections_bookmark_outlined,
          title: l10n.collectionsEmpty,
        ),
      );
    }
    final q = _query.trim().toLowerCase();
    final visible = items
        .where((c) => q.isEmpty || c.name.toLowerCase().contains(q))
        .toList();
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: StatusView(icon: Icons.search_off, title: l10n.noMatches),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: visible.length,
      itemBuilder: (BuildContext context, int index) {
        final c = visible[index];
        final state =
            _desired[c.id] ?? membershipOf(c.seriesIds, widget.seriesIds);
        final hitCount = _isBatch
            ? widget.seriesIds.where(c.seriesIds.contains).length
            : 0;
        final subtitle = state == MembershipState.partial
            ? l10n.collectionsPartialMember(hitCount)
            : l10n.seriesCount(c.seriesCount);
        return CheckboxListTile(
          key: Key('collection-pick-${c.id}'),
          tristate: _isBatch,
          value: state == MembershipState.partial
              ? null
              : state == MembershipState.all,
          onChanged: _saving ? null : (_) => _toggle(c),
          secondary: CollectionCovers(
            collectionId: c.id,
            name: c.name,
            seriesIds: c.seriesIds,
          ),
          title: _ellipsisText(c.name),
          subtitle: _ellipsisText(subtitle),
        );
      },
    );
  }

  Widget _ellipsisText(String text) =>
      Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
}
