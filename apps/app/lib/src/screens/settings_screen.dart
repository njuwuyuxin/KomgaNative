import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:material_ui/material_ui.dart';

/// 设置页：外观 + 多服务器 + 存储 + 关于。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final session = ref.watch(sessionProvider);
    final current = session is SessionConnected ? session.server : null;
    final servers =
        ref.watch(serverListProvider).value ?? const <StoredServer>[];
    final usage = ref.watch(cacheUsageProvider);
    final downloads = ref.watch(downloadsUsageProvider).value;
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
          const _SectionHeader('Servers'),
          if (servers.isEmpty)
            const ListTile(
              title: Text('No saved servers'),
              subtitle: Text('Connect to a Komga server to get started'),
            ),
          for (final item in servers)
            ListTile(
              key: Key('server-${item.id}'),
              leading: Icon(
                item.id == current?.id
                    ? Icons.check_circle
                    : Icons.dns_outlined,
                color: item.id == current?.id
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(item.label),
              subtitle: Text(item.address.baseUrl),
              trailing: IconButton(
                key: Key('server-remove-${item.id}'),
                tooltip: 'Remove server',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeServer(context, ref, item),
              ),
              onTap: item.id == current?.id
                  ? null
                  : () => ref.read(sessionProvider.notifier).switchTo(item),
            ),
          ListTile(
            key: const Key('server-add'),
            leading: const Icon(Icons.add),
            title: const Text('Add server'),
            subtitle: const Text('Signs out of the current server'),
            onTap: () => ref.read(sessionProvider.notifier).signOut(),
          ),
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
          ListTile(
            title: const Text('Downloaded books'),
            subtitle: Text(
              downloads == null
                  ? '—'
                  : '${downloads.entries} books · ${downloads.humanSize}',
            ),
            leading: const Icon(Icons.download_done_outlined),
          ),
          const Divider(),
          const _SectionHeader('About'),
          const ListTile(title: Text('Version'), trailing: Text('0.1.0 (v1)')),
          ListTile(
            key: const Key('settings-licenses'),
            leading: const Icon(Icons.description_outlined),
            title: const Text('Open source licenses'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'KomgaNative',
              applicationVersion: '0.1.0',
            ),
          ),
        ],
      ),
    );
  }
}

/// 清空离线内容。缓存是"可再生"的：清掉只影响断网能看什么，不影响进度。
Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
  await ref.read(httpCacheProvider).clear();
  ref.invalidate(cacheUsageProvider);
  ref.invalidate(downloadsUsageProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Offline content cleared')));
}

/// 删除一台已保存的服务器（需要确认：删掉就要重新输入地址和 Key）。
Future<void> _removeServer(
  BuildContext context,
  WidgetRef ref,
  StoredServer server,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('Remove server?'),
      content: Text(
        '${server.address.baseUrl} will be removed from this device. '
        'You can add it again later.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (!(confirmed ?? false)) return;

  final session = ref.read(sessionProvider);
  await ref.read(serverStoreProvider).remove(server);
  ref.invalidate(serverListProvider);
  if (session is SessionConnected && session.server.id == server.id) {
    await ref.read(sessionProvider.notifier).signOut();
  }
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
