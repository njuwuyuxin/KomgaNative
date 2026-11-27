import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/prefs_backup.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/settings_backup_controller.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 设置页的"备份"分组（SET-02）：导出到剪贴板 / 从剪贴板导入。
///
/// 编排与原子回滚交由 [SettingsBackupController] 承担，本 Widget 只负责弹窗、剪贴板与提示。
class SettingsBackupSection extends ConsumerWidget {
  const SettingsBackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AppListGroup(
      header: l10n.settingsBackup,
      children: <Widget>[
        ListTile(
          key: const Key('settings-export-prefs'),
          leading: const Icon(Icons.upload_outlined),
          title: Text(l10n.settingsExportPrefs),
          subtitle: Text(l10n.settingsExportPrefsHint),
          onTap: () => unawaited(_export(context, ref, l10n)),
        ),
        ListTile(
          key: const Key('settings-import-prefs'),
          leading: const Icon(Icons.download_outlined),
          title: Text(l10n.settingsImportPrefs),
          subtitle: Text(l10n.settingsImportPrefsHint),
          onTap: () => unawaited(_import(context, ref, l10n)),
        ),
      ],
    );
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    try {
      final encoded = await ref
          .read(settingsBackupControllerProvider)
          .exportJson();
      await Clipboard.setData(ClipboardData(text: encoded));
      if (!context.mounted) return;
      _toast(context, l10n.settingsExportDone);
    } on Object catch (error) {
      debugPrint('SettingsBackupSection: export failed: $error');
      if (context.mounted) {
        _toast(context, l10n.failureTitle(failureKindOf(error)));
      }
    }
  }

  Future<void> _import(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('settings-import-confirm'),
        title: Text(l10n.settingsImportPrefs),
        content: Text(l10n.settingsImportPrefsBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('settings-import-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsImportConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      if (context.mounted) _toast(context, l10n.settingsImportEmpty);
      return;
    }
    if (!context.mounted) return;
    try {
      await ref.read(settingsBackupControllerProvider).importJson(text);
      if (context.mounted) _toast(context, l10n.settingsImportDone);
    } on PrefsBackupException catch (error) {
      if (context.mounted) _toast(context, _backupErrorText(l10n, error));
    } on Object catch (error) {
      debugPrint('SettingsBackupSection: import failed: $error');
      if (context.mounted) {
        _toast(context, l10n.failureTitle(failureKindOf(error)));
      }
    }
  }

  String _backupErrorText(AppLocalizations l10n, PrefsBackupException error) =>
      switch (error.kind) {
        PrefsBackupErrorKind.invalidJson => l10n.backupErrorInvalidJson,
        PrefsBackupErrorKind.invalidFormat => l10n.backupErrorInvalidFormat,
        PrefsBackupErrorKind.unsupportedVersion =>
          l10n.backupErrorUnsupportedVersion(error.version ?? 0),
        PrefsBackupErrorKind.invalidPrefs => l10n.backupErrorInvalidPrefs,
      };

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
