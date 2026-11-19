import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/screens/downloads_screen.dart';
import 'package:komga_native/src/session/server_store.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:material_ui/material_ui.dart';

/// 设置页：外观 + 多服务器 + 存储 + 关于。
///
/// 版式按 iOS 的"inset grouped"：每个分组是一张圆角卡（[AppListGroup]），
/// 分组说明留在卡外；主题/语言用玻璃分段控件，与书架、导航条同一套材质。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
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
              ? l10n.nothingCachedYet
              : l10n.cachedItems(cacheUsage.humanSize, cacheUsage.entries))
        : (usage.hasError ? l10n.unavailable : l10n.calculating);

    return Scaffold(
      body: GlassPageBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(title: Text(l10n.settingsTitle)),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              sliver: SliverList.list(
                children: <Widget>[
                  AppListGroup(
                    header: l10n.appearance,
                    children: <Widget>[
                      ListTile(
                        title: Text(l10n.theme),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: GlassSegmentedControl<ThemeMode>(
                            segments: <GlassSegment<ThemeMode>>[
                              GlassSegment<ThemeMode>(
                                value: ThemeMode.system,
                                label: l10n.themeSystem,
                              ),
                              GlassSegment<ThemeMode>(
                                value: ThemeMode.light,
                                label: l10n.themeLight,
                              ),
                              GlassSegment<ThemeMode>(
                                value: ThemeMode.dark,
                                label: l10n.themeDark,
                              ),
                            ],
                            selected: settings.themeMode,
                            onSelected: controller.setThemeMode,
                          ),
                        ),
                      ),
                      ListTile(
                        key: const Key('settings-language'),
                        title: Text(l10n.language),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: GlassSegmentedControl<AppLanguage>(
                            segments: <GlassSegment<AppLanguage>>[
                              GlassSegment<AppLanguage>(
                                value: AppLanguage.system,
                                label: l10n.languageSystem,
                              ),
                              GlassSegment<AppLanguage>(
                                value: AppLanguage.en,
                                label: l10n.languageEnglish,
                              ),
                              GlassSegment<AppLanguage>(
                                value: AppLanguage.zh,
                                label: l10n.languageChinese,
                              ),
                            ],
                            selected: settings.language,
                            onSelected: controller.setLanguage,
                          ),
                        ),
                      ),
                      SwitchListTile(
                        value: settings.forceEink,
                        onChanged: controller.setForceEink,
                        title: Text(l10n.einkMode),
                        subtitle: Text(l10n.einkModeHint),
                      ),
                      SwitchListTile(
                        key: const Key('settings-haptics'),
                        value: settings.haptics,
                        onChanged: controller.setHaptics,
                        title: Text(l10n.haptics),
                        subtitle: Text(l10n.hapticsHint),
                      ),
                    ],
                  ),
                  AppListGroup(
                    header: l10n.servers,
                    children: <Widget>[
                      if (servers.isEmpty)
                        ListTile(
                          title: Text(l10n.noSavedServers),
                          subtitle: Text(l10n.noSavedServersHint),
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
                            tooltip: l10n.removeServerTooltip,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeServer(context, ref, item),
                          ),
                          onTap: item.id == current?.id
                              ? null
                              : () => ref
                                    .read(sessionProvider.notifier)
                                    .switchTo(item),
                        ),
                      ListTile(
                        key: const Key('server-add'),
                        leading: const Icon(Icons.add),
                        title: Text(l10n.addServer),
                        subtitle: Text(l10n.addServerHint),
                        onTap: () =>
                            ref.read(sessionProvider.notifier).signOut(),
                      ),
                    ],
                  ),
                  AppListGroup(
                    header: l10n.storage,
                    children: <Widget>[
                      ListTile(
                        title: Text(l10n.offlineContent),
                        subtitle: Text(cacheSubtitle),
                        leading: const Icon(Icons.sd_storage_outlined),
                        trailing: TextButton(
                          onPressed: cacheUsage == null || cacheUsage.isEmpty
                              ? null
                              : () => _clearCache(context, ref),
                          child: Text(l10n.clear),
                        ),
                      ),
                      ListTile(
                        key: const Key('settings-downloads'),
                        title: Text(l10n.downloadedBooks),
                        subtitle: Text(
                          downloads == null
                              ? '—'
                              : l10n.downloadedUsage(
                                  downloads.entries,
                                  downloads.humanSize,
                                ),
                        ),
                        leading: const Icon(Icons.download_done_outlined),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                const DownloadsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  AppListGroup(
                    header: l10n.about,
                    children: <Widget>[
                      ListTile(
                        title: Text(l10n.version),
                        trailing: const Text('0.1.0 (v1)'),
                      ),
                      ListTile(
                        key: const Key('settings-licenses'),
                        leading: const Icon(Icons.description_outlined),
                        title: Text(l10n.openSourceLicenses),
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'KomgaNative',
                          applicationVersion: '0.1.0',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 悬浮导航条压在内容之上：最后一块要能让开它。
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSizes.navBarClearance),
            ),
          ],
        ),
      ),
    );
  }
}

/// 清空离线内容。缓存是"可再生"的：清掉只影响断网能看什么，不影响进度。
Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  await ref.read(httpCacheProvider).clear();
  ref.invalidate(cacheUsageProvider);
  ref.invalidate(downloadsUsageProvider);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(l10n.offlineContentCleared)));
}

/// 删除一台已保存的服务器（需要确认：删掉就要重新输入地址和 Key）。
Future<void> _removeServer(
  BuildContext context,
  WidgetRef ref,
  StoredServer server,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final l10n = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(l10n.removeServerTitle),
        content: Text(l10n.removeServerBody(server.address.baseUrl)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.remove),
          ),
        ],
      );
    },
  );
  if (!(confirmed ?? false)) return;

  final session = ref.read(sessionProvider);
  await ref.read(serverStoreProvider).remove(server);
  ref.invalidate(serverListProvider);
  if (session is SessionConnected && session.server.id == server.id) {
    await ref.read(sessionProvider.notifier).signOut();
  }
}
