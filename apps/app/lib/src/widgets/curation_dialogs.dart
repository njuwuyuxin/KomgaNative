import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集命名 / 重命名弹窗。
Future<String?> promptCollectionName(
  BuildContext context, {
  required String title,
  String initial = '',
  Key? dialogKey,
  Key? fieldKey,
  Key? okKey,
}) async {
  final l10n = AppLocalizations.of(context);
  var draft = initial;
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      key: dialogKey,
      title: Text(title),
      content: TextFormField(
        key: fieldKey,
        initialValue: initial,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onChanged: (String value) => draft = value,
        onFieldSubmitted: (_) => Navigator.of(context).pop(draft.trim()),
        decoration: InputDecoration(hintText: l10n.collectionNameHint),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: okKey,
          onPressed: () => Navigator.of(context).pop(draft.trim()),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
}

/// 删除收藏集确认弹窗。
Future<bool> confirmCollectionDelete(BuildContext context, String name) {
  final l10n = AppLocalizations.of(context);
  return confirmDestructiveCuration(
    context,
    title: l10n.collectionDeleteTitle,
    body: l10n.collectionDeleteBody(name),
    confirmLabel: l10n.delete,
    dialogKey: const Key('collection-delete-confirm'),
    okKey: const Key('collection-delete-ok'),
  );
}

/// 阅读列表新建 / 编辑（名称 + 可选简介）弹窗。
Future<({String name, String summary})?> promptReadListForm(
  BuildContext context, {
  required String title,
  String initialName = '',
  String initialSummary = '',
  Key? dialogKey,
  Key? nameKey,
  Key? summaryKey,
  Key? okKey,
}) async {
  final l10n = AppLocalizations.of(context);
  var name = initialName;
  var summary = initialSummary;
  return showDialog<({String name, String summary})>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      key: dialogKey ?? const Key('readlist-form-dialog'),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextFormField(
            key: nameKey ?? const Key('readlist-name-field'),
            initialValue: initialName,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: (String value) => name = value,
            decoration: InputDecoration(hintText: l10n.readListNameHint),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: summaryKey ?? const Key('readlist-summary-field'),
            initialValue: initialSummary,
            maxLines: 2,
            onChanged: (String value) => summary = value,
            decoration: InputDecoration(hintText: l10n.readListSummaryHint),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: okKey ?? const Key('readlist-form-ok'),
          onPressed: () {
            final trimmed = name.trim();
            if (trimmed.isEmpty) return;
            Navigator.of(context).pop((name: trimmed, summary: summary.trim()));
          },
          child: Text(l10n.save),
        ),
      ],
    ),
  );
}

/// 删除阅读列表确认弹窗。
Future<bool> confirmReadListDelete(BuildContext context, String name) {
  final l10n = AppLocalizations.of(context);
  return confirmDestructiveCuration(
    context,
    title: l10n.readListDeleteTitle,
    body: l10n.readListDeleteBody(name),
    confirmLabel: l10n.delete,
    dialogKey: const Key('readlist-delete-confirm'),
    okKey: const Key('readlist-delete-ok'),
  );
}

/// 通用的删除/清空确认弹窗（含移出最后一项会导致集合被删的场景）。
Future<bool> confirmDestructiveCuration(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  Key? dialogKey,
  Key? okKey,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      key: dialogKey,
      title: Text(title),
      content: Text(body),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: okKey,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}
