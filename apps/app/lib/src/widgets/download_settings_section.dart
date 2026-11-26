import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/app_settings.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:material_ui/material_ui.dart';

/// 设置页的"下载"分组（DLD-01）：仅 Wi-Fi / 读完自动删除 / 并发数。
///
/// 三个值都写进同一个 `AppSettings` 快照（`_store.update`），改完让
/// [downloadPolicyProvider] 失效，正在跑的下载不会被中断，下一个补位按新并发数来。
class DownloadSettingsSection extends ConsumerWidget {
  const DownloadSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 这里用 `downloadPolicyProvider` 而不是 SettingsState：那里面只有外观/语言。
    final policy = ref.watch(downloadPolicyProvider).value;
    final settingsController = ref.read(settingsProvider.notifier);

    void write(AppSettings Function(AppSettings) mutate) {
      unawaited(settingsController.updateSettings(mutate));
      ref.invalidate(downloadPolicyProvider);
    }

    return AppListGroup(
      header: l10n.downloadsSection,
      children: <Widget>[
        SwitchListTile(
          key: const Key('settings-download-wifi-only'),
          value: policy?.wifiOnly ?? false,
          title: Text(l10n.downloadWifiOnly),
          subtitle: Text(l10n.downloadWifiOnlyHint),
          onChanged: (bool value) =>
              write((AppSettings s) => s.copyWith(downloadWifiOnly: value)),
        ),
        SwitchListTile(
          key: const Key('settings-download-auto-delete'),
          value: policy?.autoDeleteRead ?? false,
          title: Text(l10n.downloadAutoDeleteRead),
          subtitle: Text(l10n.downloadAutoDeleteReadHint),
          onChanged: (bool value) => write(
            (AppSettings s) => s.copyWith(downloadAutoDeleteRead: value),
          ),
        ),
        ListTile(
          key: const Key('settings-download-concurrency'),
          title: Text(l10n.downloadConcurrency),
          subtitle: Text(
            '${policy?.concurrency ?? 1}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 1, label: Text('1')),
              ButtonSegment<int>(value: 2, label: Text('2')),
              ButtonSegment<int>(value: 3, label: Text('3')),
            ],
            selected: <int>{policy?.concurrency ?? 1},
            showSelectedIcon: false,
            onSelectionChanged: (Set<int> value) => write(
              (AppSettings s) =>
                  s.copyWith(downloadConcurrency: value.first.clamp(1, 3)),
            ),
          ),
        ),
      ],
    );
  }
}
