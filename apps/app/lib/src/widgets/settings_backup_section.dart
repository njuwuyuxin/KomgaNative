import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/prefs_backup.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_native/src/providers/pinned_series_provider.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:material_ui/material_ui.dart';

/// 设置页的"备份"分组（SET-02）：导出到剪贴板 / 从剪贴板导入。
///
/// 为什么用剪贴板而不是文件：
/// - 不引入 `share_plus` / `file_picker` 这类新依赖（AGENTS.md：新增依赖先写 ADR）；
/// - 手机上一份几千字节的 JSON，复制粘贴比"找文件"更快；
/// - 导出内容里**没有任何凭据**，贴到聊天窗口里也不怕。
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
    final backup = PrefsBackup.of(
      reader: ref.read(readerPrefsProvider),
      // AppSettings 是**持久化快照**，由控制器读取，UI 不直接碰 Store。
      settings: await ref.read(settingsProvider.notifier).loadSnapshot(),
      pinnedSeries: await ref.read(pinnedSeriesControllerProvider).currentIds(),
    );
    await Clipboard.setData(ClipboardData(text: backup.encode()));
    if (!context.mounted) return;
    _toast(context, l10n.settingsExportDone);
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
      final backup = PrefsBackup.decode(text);
      // 先全部解析成功再落盘：坏文件绝不能把现有设置改成半截。
      final prefs = backup.toReaderPrefs();
      final settings = backup.toAppSettings();
      await ref.read(readerPrefsProvider.notifier).replaceAll(prefs);
      await ref.read(settingsProvider.notifier).replaceAll(settings);
      if (backup.pinnedSeries != null) {
        await ref
            .read(pinnedSeriesControllerProvider)
            .replaceAll(backup.pinnedSeries!);
      }
      ref.invalidate(downloadPolicyProvider);
      if (context.mounted) _toast(context, l10n.settingsImportDone);
    } on PrefsBackupException catch (error) {
      if (context.mounted) _toast(context, error.message);
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
