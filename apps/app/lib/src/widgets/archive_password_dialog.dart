import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/archive_password_provider.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 用户在加密归档/PDF 密码弹窗中提交的结果（LMB-13）。
final class ArchivePasswordSubmission {
  const ArchivePasswordSubmission({
    required this.password,
    required this.saveToDictionary,
  });

  final String password;
  final bool saveToDictionary;
}

/// 弹出加密漫画归档 / 加密 PDF 解锁密码输入框。
Future<ArchivePasswordSubmission?> showArchivePasswordDialog(
  BuildContext context, {
  required String fileName,
  bool wrongAttempt = false,
}) {
  return showDialog<ArchivePasswordSubmission>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) =>
        _ArchivePasswordDialog(fileName: fileName, wrongAttempt: wrongAttempt),
  );
}

class _ArchivePasswordDialog extends StatefulWidget {
  const _ArchivePasswordDialog({
    required this.fileName,
    required this.wrongAttempt,
  });

  final String fileName;
  final bool wrongAttempt;

  @override
  State<_ArchivePasswordDialog> createState() => _ArchivePasswordDialogState();
}

class _ArchivePasswordDialogState extends State<_ArchivePasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  bool _saveToDict = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final pwd = _controller.text;
    if (pwd.isEmpty) return;
    Navigator.of(context).pop(
      ArchivePasswordSubmission(password: pwd, saveToDictionary: _saveToDict),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('archive-password-dialog'),
      title: Text(l10n.archivePasswordTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              l10n.archivePasswordPrompt(widget.fileName),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('archive-password-field'),
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.archivePasswordLabel,
                errorText: widget.wrongAttempt
                    ? l10n.archivePasswordWrong
                    : null,
                suffixIcon: IconButton(
                  key: const Key('archive-password-visibility'),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            CheckboxListTile(
              key: const Key('archive-pwd-save-dict'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _saveToDict,
              onChanged: (bool? v) => setState(() => _saveToDict = v ?? true),
              title: Text(
                l10n.archivePasswordSaveToDict,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('archive-password-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('archive-password-submit'),
          onPressed: _submit,
          child: Text(l10n.archivePasswordUnlock),
        ),
      ],
    );
  }
}

/// 常用解压密码词典管理面板（在「本地书库管理中心」中打开）。
Future<void> showPasswordDictionarySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (BuildContext context) {
      final theme = Theme.of(context);
      final eink = AppTheme.isEink(theme);
      return FrostedSurface(
        kind: AppMaterialKind.sheet,
        material: AppMaterial.resolve(
          AppMaterialKind.sheet,
          eink: eink,
          dark: theme.brightness == Brightness.dark,
        ),
        shape: AppShapes.sheet(eink: eink),
        child: const Material(
          type: MaterialType.transparency,
          child: _PasswordDictionarySheet(),
        ),
      );
    },
  );
}

class _PasswordDictionarySheet extends ConsumerStatefulWidget {
  const _PasswordDictionarySheet();

  @override
  ConsumerState<_PasswordDictionarySheet> createState() =>
      _PasswordDictionarySheetState();
}

class _PasswordDictionarySheetState
    extends ConsumerState<_PasswordDictionarySheet> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref.read(commonPasswordsProvider.notifier).add(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = AppTypography.of(context);
    final theme = Theme.of(context);
    final list = ref.watch(commonPasswordsProvider).value ?? const <String>[];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    l10n.passwordDictionaryTitle,
                    style: typography.headline,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(
              l10n.passwordDictionaryHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const Key('pwd-dict-input'),
                    controller: _input,
                    onSubmitted: (_) => unawaited(_add()),
                    decoration: InputDecoration(
                      labelText: l10n.passwordDictionaryAddHint,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  key: const Key('pwd-dict-add'),
                  onPressed: () => unawaited(_add()),
                  child: Text(l10n.passwordDictionaryAddButton),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  l10n.passwordDictionaryEmpty,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (BuildContext context, int index) {
                    final pwd = list[index];
                    return ListTile(
                      key: Key('pwd-dict-item-$index'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.vpn_key_outlined),
                      title: Text(
                        pwd,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        key: Key('pwd-dict-delete-$index'),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.delete,
                        onPressed: () => unawaited(
                          ref
                              .read(commonPasswordsProvider.notifier)
                              .remove(pwd),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
