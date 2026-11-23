import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/curation_ops.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/l10n/failure_text.dart';
import 'package:komga_native/src/providers/collections_controller.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/collection_covers.dart';
import 'package:komga_native/src/widgets/curation_dialogs.dart';
import 'package:material_ui/material_ui.dart';

/// 弹出「添加到收藏集」勾选面板，支持单个系列或批量多选系列。
///
/// 返回 `true` 表示服务端收藏集已发生更新。
Future<bool> showCollectionPickerSheet(
  BuildContext context, {
  required List<String> seriesIds,
}) async {
  if (seriesIds.isEmpty) return false;
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (BuildContext context) =>
        _CollectionPickerSheet(seriesIds: seriesIds),
  );
  return changed == true;
}

class _CollectionPickerSheet extends ConsumerStatefulWidget {
  const _CollectionPickerSheet({required this.seriesIds});

  final List<String> seriesIds;

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

  MembershipChangePlan _planFor(List<KomgaCollection> collections) =>
      planMembershipChanges(
        containers: <({String id, String name, List<String> memberIds})>[
          for (final c in collections)
            (id: c.id, name: c.name, memberIds: c.seriesIds),
        ],
        targetIds: widget.seriesIds,
        desiredStates: _desired,
      );

  void _toggle(KomgaCollection collection) {
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

  Future<void> _createNew(List<KomgaCollection> current) async {
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
      final created = await ref
          .read(collectionsControllerProvider.notifier)
          .create(name: name, seriesIds: widget.seriesIds);
      if (!mounted) return;
      final hasPendingEdits = !_planFor(current).isEmpty;
      if (!hasPendingEdits) {
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.collectionAddedTo(created.name))),
        );
      } else {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.collectionAddedTo(created.name))),
        );
      }
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<void> _save(List<KomgaCollection> collections) async {
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
          .applyCollectionPlan(plan, affectedSeriesIds: widget.seriesIds);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.collectionSaved)));
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
    final async = ref.watch(allCollectionsProvider);
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
                            _createNew(items ?? const <KomgaCollection>[]),
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
            Flexible(child: _buildBody(context, l10n, async)),
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
    AsyncValue<List<KomgaCollection>> async,
  ) {
    if (async.hasError && !async.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: StatusView(
          icon: Icons.cloud_off_outlined,
          title: l10n.failureTitle(failureKindOf(async.error)),
          actionLabel: l10n.retry,
          onAction: () => ref.invalidate(allCollectionsProvider),
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
    final visible = <KomgaCollection>[
      for (final c in items)
        if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
    ];
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
        final collection = visible[index];
        final initial = membershipOf(collection.seriesIds, widget.seriesIds);
        final state = _desired[collection.id] ?? initial;
        final bool? value = switch (state) {
          MembershipState.all => true,
          MembershipState.none => false,
          MembershipState.partial => null,
        };
        final hitCount = _isBatch
            ? widget.seriesIds.where(collection.seriesIds.contains).length
            : 0;
        final subtitle = state == MembershipState.partial
            ? l10n.collectionsPartialMember(hitCount)
            : l10n.seriesCount(collection.seriesCount);
        return CheckboxListTile(
          key: Key('collection-pick-${collection.id}'),
          tristate: _isBatch,
          value: value,
          onChanged: _saving ? null : (_) => _toggle(collection),
          secondary: CollectionCovers(
            collectionId: collection.id,
            name: collection.name,
            seriesIds: collection.seriesIds,
          ),
          title: Text(
            collection.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
