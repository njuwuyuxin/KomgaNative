import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/curation_ops.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/widgets/curation_dialogs.dart';
import 'package:yomu/src/widgets/picker_sheet_shell.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 通用「成员归属勾选面板」（收藏集 / 阅读列表共用，P2-7）。
///
/// 统一托管三态勾选（单选 / 批量）、搜索过滤、空容器删除确认、
/// 保存提交与错误提示；具体容器类型 [T] 的数据源与写操作由调用方注入。
class MembershipPickerSheet<T> extends StatefulWidget {
  const MembershipPickerSheet({
    super.key,
    required this.asyncItems,
    required this.targetIds,
    required this.itemId,
    required this.itemName,
    required this.itemMemberIds,
    required this.sheetKey,
    required this.createButtonKey,
    required this.searchFieldKey,
    required this.saveButtonKey,
    required this.itemKeyPrefix,
    required this.emptyDeleteDialogKey,
    required this.emptyDeleteOkKey,
    required this.title,
    required this.createLabel,
    required this.searchHint,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyDeleteTitle,
    required this.emptyDeleteBody,
    required this.savedMessage,
    required this.buildSecondary,
    required this.buildSubtitle,
    required this.onRetry,
    required this.onCreate,
    required this.onApplyPlan,
  });

  final AsyncValue<List<T>> asyncItems;
  final List<String> targetIds;
  final String Function(T item) itemId;
  final String Function(T item) itemName;
  final List<String> Function(T item) itemMemberIds;

  final Key sheetKey;
  final Key createButtonKey;
  final Key searchFieldKey;
  final Key saveButtonKey;
  final String itemKeyPrefix;
  final Key emptyDeleteDialogKey;
  final Key emptyDeleteOkKey;

  final String title;
  final String createLabel;
  final String searchHint;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyDeleteTitle;
  final String Function(String names) emptyDeleteBody;
  final String Function(MembershipChangePlan plan) savedMessage;

  final Widget Function(T item) buildSecondary;
  final String Function(T item, MembershipState state, int hitCount)
  buildSubtitle;
  final VoidCallback onRetry;

  /// 新建容器回调：先弹窗采集输入，确认后再调用 `markSaving()` 进入提交态并返回提示文案；取消返回 `null`。
  final Future<String?> Function(BuildContext context, VoidCallback markSaving)
  onCreate;
  final Future<void> Function(MembershipChangePlan plan) onApplyPlan;

  @override
  State<MembershipPickerSheet<T>> createState() =>
      _MembershipPickerSheetState<T>();
}

class _MembershipPickerSheetState<T> extends State<MembershipPickerSheet<T>> {
  final Map<String, MembershipState> _desired = <String, MembershipState>{};
  String _query = '';
  bool _saving = false;

  bool get _isBatch => widget.targetIds.length > 1;

  MembershipChangePlan _planFor(List<T> items) => planMembershipChanges(
    containers: <({String id, String name, List<String> memberIds})>[
      for (final item in items)
        (
          id: widget.itemId(item),
          name: widget.itemName(item),
          memberIds: widget.itemMemberIds(item),
        ),
    ],
    targetIds: widget.targetIds,
    desiredStates: _desired,
  );

  void _toggle(T item) {
    unawaited(AppHaptics.selection());
    final id = widget.itemId(item);
    final initial = membershipOf(widget.itemMemberIds(item), widget.targetIds);
    final current = _desired[id] ?? initial;
    final next = current == MembershipState.all
        ? MembershipState.none
        : MembershipState.all;
    setState(() {
      if (next == initial) {
        _desired.remove(id);
      } else {
        _desired[id] = next;
      }
    });
  }

  Future<void> _createNew(List<T> current) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await widget.onCreate(context, () {
        if (mounted) setState(() => _saving = true);
      });
      if (!mounted) return;
      if (message == null) {
        if (_saving) setState(() => _saving = false);
        return;
      }
      final hasPendingEdits = !_planFor(current).isEmpty;
      if (!hasPendingEdits) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _saving = false);
      }
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

  Future<void> _save(List<T> items) async {
    final plan = _planFor(items);
    if (plan.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (plan.deletions.isNotEmpty) {
      final names = plan.deletions.map((d) => d.name).join('、');
      final ok = await confirmDestructiveCuration(
        context,
        title: widget.emptyDeleteTitle,
        body: widget.emptyDeleteBody(names),
        confirmLabel: l10n.delete,
        dialogKey: widget.emptyDeleteDialogKey,
        okKey: widget.emptyDeleteOkKey,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onApplyPlan(plan);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(widget.savedMessage(plan))));
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
    final items = widget.asyncItems.value;
    final hasChanges = items != null && !_planFor(items).isEmpty;

    return PickerSheetShell(
      sheetKey: widget.sheetKey,
      maxHeightFactor: 0.72,
      title: widget.title,
      headerAction: TextButton.icon(
        key: widget.createButtonKey,
        onPressed: _saving
            ? null
            : () => unawaited(_createNew(items ?? List<T>.empty())),
        icon: const Icon(Icons.add, size: AppSizes.iconSm),
        label: Text(widget.createLabel),
      ),
      showSearch: items != null && items.length > 5,
      searchKey: widget.searchFieldKey,
      searchHint: widget.searchHint,
      onSearchChanged: (String v) => setState(() => _query = v),
      body: _buildBody(l10n, widget.asyncItems),
      footer: FilledButton(
        key: widget.saveButtonKey,
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
    );
  }

  Widget _buildBody(AppLocalizations l10n, AsyncValue<List<T>> async) {
    if (async.hasError && !async.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: StatusView(
          icon: Icons.cloud_off_outlined,
          title: l10n.failureTitle(failureKindOf(async.error)),
          actionLabel: l10n.retry,
          onAction: widget.onRetry,
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
        child: StatusView(icon: widget.emptyIcon, title: widget.emptyTitle),
      );
    }
    final q = _query.trim().toLowerCase();
    final visible = <T>[
      for (final item in items)
        if (q.isEmpty || widget.itemName(item).toLowerCase().contains(q)) item,
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
        final item = visible[index];
        final id = widget.itemId(item);
        final members = widget.itemMemberIds(item);
        final state = _desired[id] ?? membershipOf(members, widget.targetIds);
        final hitCount = _isBatch
            ? widget.targetIds.where(members.contains).length
            : 0;
        final subtitle = widget.buildSubtitle(item, state, hitCount);
        return CheckboxListTile(
          key: Key('${widget.itemKeyPrefix}$id'),
          tristate: _isBatch,
          value: state == MembershipState.partial
              ? null
              : state == MembershipState.all,
          onChanged: _saving ? null : (_) => _toggle(item),
          secondary: widget.buildSecondary(item),
          title: Text(
            widget.itemName(item),
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
