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
import 'package:komga_native/src/widgets/curation_dialogs.dart';
import 'package:material_ui/material_ui.dart';

/// 弹出「添加到阅读列表」勾选面板，支持单本书或批量多选书。
///
/// 返回 `true` 表示服务端阅读列表已发生更新。
Future<bool> showReadListPickerSheet(
  BuildContext context, {
  required List<String> bookIds,
}) async {
  if (bookIds.isEmpty) return false;
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (BuildContext context) => _ReadListPickerSheet(bookIds: bookIds),
  );
  return changed == true;
}

class _ReadListPickerSheet extends ConsumerStatefulWidget {
  const _ReadListPickerSheet({required this.bookIds});

  final List<String> bookIds;

  @override
  ConsumerState<_ReadListPickerSheet> createState() =>
      _ReadListPickerSheetState();
}

class _ReadListPickerSheetState extends ConsumerState<_ReadListPickerSheet> {
  final Map<String, MembershipState> _desired = <String, MembershipState>{};
  String _query = '';
  bool _saving = false;

  bool get _isBatch => widget.bookIds.length > 1;

  MembershipChangePlan _planFor(List<ReadList> lists) => planMembershipChanges(
    containers: <({String id, String name, List<String> memberIds})>[
      for (final list in lists)
        (id: list.id, name: list.name, memberIds: list.bookIds),
    ],
    targetIds: widget.bookIds,
    desiredStates: _desired,
  );

  void _toggle(ReadList list) {
    unawaited(AppHaptics.selection());
    final initial = membershipOf(list.bookIds, widget.bookIds);
    final current = _desired[list.id] ?? initial;
    final next = current == MembershipState.all
        ? MembershipState.none
        : MembershipState.all;
    setState(() {
      if (next == initial) {
        _desired.remove(list.id);
      } else {
        _desired[list.id] = next;
      }
    });
  }

  Future<void> _createNew(List<ReadList> current) async {
    final l10n = AppLocalizations.of(context);
    final form = await promptReadListForm(
      context,
      title: l10n.readListCreate,
      dialogKey: const Key('readlist-create-dialog'),
      nameKey: const Key('readlist-create-name'),
      summaryKey: const Key('readlist-create-summary'),
      okKey: const Key('readlist-create-ok'),
    );
    if (form == null || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final created = await ref
          .read(collectionsControllerProvider.notifier)
          .createReadList(
            name: form.name,
            summary: form.summary,
            bookIds: widget.bookIds,
          );
      if (!mounted) return;
      final hasPendingEdits = !_planFor(current).isEmpty;
      if (!hasPendingEdits) {
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.readListAddedTo(created.name))),
        );
      } else {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.readListAddedTo(created.name))),
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

  Future<void> _save(List<ReadList> lists) async {
    final plan = _planFor(lists);
    if (plan.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (plan.deletions.isNotEmpty) {
      final names = plan.deletions.map((d) => d.name).join('、');
      final ok = await confirmDestructiveCuration(
        context,
        title: l10n.readListEmptyDeleteTitle,
        body: l10n.readListEmptyDeleteBody(names),
        confirmLabel: l10n.delete,
        dialogKey: const Key('readlist-empty-delete-confirm'),
        okKey: const Key('readlist-empty-delete-ok'),
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .applyReadListPlan(plan);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.readListSaved)));
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
    final async = ref.watch(allReadListsProvider);
    final items = async.value;
    final hasChanges = items != null && !_planFor(items).isEmpty;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return ConstrainedBox(
      key: const Key('readlist-picker-sheet'),
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
                      l10n.addToReadList,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('readlist-picker-create'),
                    onPressed: _saving
                        ? null
                        : () => unawaited(
                            _createNew(items ?? const <ReadList>[]),
                          ),
                    icon: const Icon(Icons.add, size: AppSizes.iconSm),
                    label: Text(l10n.readListCreate),
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
                  key: const Key('readlist-picker-search'),
                  onChanged: (String v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l10n.searchReadListsHint,
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
                  key: const Key('readlist-picker-save'),
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
    AsyncValue<List<ReadList>> async,
  ) {
    if (async.hasError && !async.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: StatusView(
          icon: Icons.cloud_off_outlined,
          title: l10n.failureTitle(failureKindOf(async.error)),
          actionLabel: l10n.retry,
          onAction: () => ref.invalidate(allReadListsProvider),
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
          icon: Icons.list_alt_outlined,
          title: l10n.readListsEmpty,
        ),
      );
    }
    final q = _query.trim().toLowerCase();
    final visible = <ReadList>[
      for (final list in items)
        if (q.isEmpty || list.name.toLowerCase().contains(q)) list,
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
        final list = visible[index];
        final initial = membershipOf(list.bookIds, widget.bookIds);
        final state = _desired[list.id] ?? initial;
        final bool? value = switch (state) {
          MembershipState.all => true,
          MembershipState.none => false,
          MembershipState.partial => null,
        };
        final hitCount = _isBatch
            ? widget.bookIds.where(list.bookIds.contains).length
            : 0;
        final subtitle = state == MembershipState.partial
            ? l10n.readListsPartialMember(hitCount)
            : list.summary.isEmpty
            ? l10n.bookCount(list.bookCount)
            : '${l10n.bookCount(list.bookCount)} · ${list.summary}';
        return CheckboxListTile(
          key: Key('readlist-pick-${list.id}'),
          tristate: _isBatch,
          value: value,
          onChanged: _saving ? null : (_) => _toggle(list),
          secondary: const Icon(Icons.list_alt_outlined),
          title: Text(list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
