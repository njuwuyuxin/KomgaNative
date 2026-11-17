import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/session/session_controller.dart';

/// 设置页：外观 + 当前连接。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final session = ref.watch(sessionProvider);
    final server = session is SessionConnected ? session.server : null;
    final usage = ref.watch(cacheUsageProvider);
    final cacheUsage = usage.value;
    // 不用 AsyncValue.when：Riverpod 3 首次失败是 AsyncLoading + hasError，
    // 按值/错误位判断才不会把"算不出来"显示成永久 loading。
    final cacheSubtitle = cacheUsage != null
        ? (cacheUsage.isEmpty
              ? 'Nothing cached yet'
              : '${cacheUsage.humanSize} · ${cacheUsage.entries} items')
        : (usage.hasError ? 'Unavailable' : 'Calculating…');

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: <Widget>[
          const _SectionHeader('Appearance'),
          ListTile(
            title: const Text('Theme'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: SegmentedButton<ThemeMode>(
                segments: const <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text('System'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text('Light'),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                  ),
                ],
                selected: <ThemeMode>{settings.themeMode},
                onSelectionChanged: (Set<ThemeMode> selection) =>
                    controller.setThemeMode(selection.first),
              ),
            ),
          ),
          SwitchListTile(
            value: settings.forceEink,
            onChanged: controller.setForceEink,
            title: const Text('E-ink mode'),
            subtitle: const Text(
              'Disable animation, shadows and color; maximize contrast',
            ),
          ),
          const Divider(),
          const _SectionHeader('Server'),
          if (server == null)
            const ListTile(
              title: Text('Not connected'),
              subtitle: Text('Go back to the connect screen to sign in again'),
            )
          else ...<Widget>[
            ListTile(
              title: Text(
                server.accountEmail.isEmpty ? 'Connected' : server.accountEmail,
              ),
              subtitle: Text(server.address.baseUrl),
              leading: const Icon(Icons.dns_outlined),
            ),
            ListTile(
              title: const Text('Disconnect'),
              leading: const Icon(Icons.logout),
              onTap: () => ref.read(sessionProvider.notifier).signOut(),
            ),
          ],
          const Divider(),
          const _SectionHeader('Storage'),
          ListTile(
            title: const Text('Offline content'),
            subtitle: Text(cacheSubtitle),
            leading: const Icon(Icons.sd_storage_outlined),
            trailing: TextButton(
              onPressed: cacheUsage == null || cacheUsage.isEmpty
                  ? null
                  : () => _clearCache(context, ref),
              child: const Text('Clear'),
            ),
          ),
          const Divider(),
          const _SectionHeader('About'),
          const ListTile(title: Text('Version'), trailing: Text('0.1.0 (M1)')),
        ],
      ),
    );
  }
}

/// 清空离线内容。缓存是"可再生"的：清掉只影响断网能看什么，不影响进度。
Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
  await ref.read(httpCacheProvider).clear();
  ref.invalidate(cacheUsageProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Offline content cleared')));
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
