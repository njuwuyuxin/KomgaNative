import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu/src/providers/local_library_center_provider.dart';
import 'package:yomu/src/widgets/archive_password_dialog.dart';
import 'package:yomu/src/widgets/local_mounted_root_tile.dart';
import 'package:yomu/src/widgets/source_group_bar.dart';
import 'package:yomu/src/widgets/wifi_transfer_sheet.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 「本地书库管理中心」（LMB-09）：
/// 集中管理外部原位挂载目录（Android SAF / iOS Bookmark / iOS Files.app）、
/// 增量扫描、`.nomedia` 保护、Wi-Fi 传书与沙盒占用统计。
class LocalLibraryCenterScreen extends ConsumerWidget {
  const LocalLibraryCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scanState = ref.watch(localLibraryScanProvider);
    final scanController = ref.read(localLibraryScanProvider.notifier);
    final roots =
        ref.watch(mountedRootsProvider).value ?? const <LocalMountedRootsRow>[];
    final usage = ref.watch(localStorageUsageProvider).value;

    return Scaffold(
      body: GlassPageBackground(
        child: CustomScrollView(
          key: const Key('local-library-center-scroll'),
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(
                bar: GlassSurface(
                  shape: AppShapes.of(context, AppShapes.bar),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        key: const Key('local-center-back'),
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        onPressed: () {
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          l10n.localLibraryCenterTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.of(context).headline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              sliver: SliverList.list(
                children: <Widget>[
                  if (scanState.scanning)
                    _ScanProgressBanner(state: scanState, l10n: l10n),
                  if (!scanState.scanning && scanState.lastSummary != null)
                    _ScanSummaryBanner(
                      summary: scanState.lastSummary!,
                      l10n: l10n,
                    ),
                  AppListGroup(
                    header: l10n.localCenterQuickActions,
                    children: <Widget>[
                      ListTile(
                        key: const Key('local-center-mount-root'),
                        leading: const Icon(Icons.drive_folder_upload_outlined),
                        title: Text(l10n.localCenterMountFolder),
                        subtitle: Text(l10n.localCenterMountFolderHint),
                        trailing: const Icon(Icons.chevron_right),
                        enabled: !scanState.scanning,
                        onTap: () =>
                            unawaited(scanController.mountExternalDirectory()),
                      ),
                      ListTile(
                        key: const Key('local-center-scan-all'),
                        leading: const Icon(Icons.sync),
                        title: Text(l10n.localCenterScanAll),
                        subtitle: Text(l10n.localCenterScanAllHint),
                        enabled: !scanState.scanning,
                        onTap: () => unawaited(scanController.scanAllRoots()),
                      ),
                      ListTile(
                        key: const Key('local-center-wifi'),
                        leading: const Icon(Icons.wifi_tethering),
                        title: Text(l10n.wifiTransferMenu),
                        subtitle: Text(l10n.localCenterWifiHint),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => unawaited(showWifiTransferSheet(context)),
                      ),
                      ListTile(
                        key: const Key('local-center-import-files'),
                        leading: const Icon(Icons.folder_zip_outlined),
                        title: Text(l10n.importArchiveFiles),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            unawaited(runLocalArchiveImport(context, ref)),
                      ),
                      ListTile(
                        key: const Key('local-center-password-dict'),
                        leading: const Icon(Icons.vpn_key_outlined),
                        title: Text(l10n.passwordDictionaryTitle),
                        subtitle: Text(l10n.passwordDictionarySubtitle),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            unawaited(showPasswordDictionarySheet(context)),
                      ),
                    ],
                  ),
                  AppListGroup(
                    key: const Key('local-center-roots-group'),
                    header: l10n.localCenterMountedRoots,
                    children: roots.isEmpty
                        ? <Widget>[
                            ListTile(
                              key: const Key('local-center-roots-empty'),
                              leading: const Icon(Icons.folder_off_outlined),
                              title: Text(l10n.localCenterNoMountedRoots),
                              subtitle: Text(
                                l10n.localCenterNoMountedRootsHint,
                              ),
                            ),
                          ]
                        : <Widget>[
                            for (final row in roots)
                              LocalMountedRootTile(
                                row: row,
                                scanning: scanState.scanning,
                                onRescan: () => unawaited(
                                  scanController.scanSingleRoot(
                                    mountedRootFromRow(row),
                                  ),
                                ),
                                onEnsureNomedia: () => unawaited(
                                  scanController.ensureNomedia(row),
                                ),
                                onUnmount: () => unawaited(
                                  confirmUnmountExternalRoot(context, ref, row),
                                ),
                              ),
                          ],
                  ),
                  AppListGroup(
                    header: l10n.storage,
                    children: <Widget>[
                      ListTile(
                        key: const Key('local-center-storage-summary'),
                        leading: const Icon(Icons.sd_storage_outlined),
                        title: Text(l10n.localComicsStorage),
                        subtitle: Text(
                          usage == null
                              ? '—'
                              : l10n.localComicsUsage(
                                  usage.entries,
                                  usage.humanSize,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanProgressBanner extends StatelessWidget {
  const _ScanProgressBanner({required this.state, required this.l10n});

  final LocalLibraryScanState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final progress = state.total > 0 ? state.scanned / state.total : null;
    final label = state.currentRootName.isEmpty
        ? l10n.localLibrary
        : state.currentRootName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: GlassSurface(
        key: const Key('local-center-scan-progress'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.localCenterScanning(label, state.scanned, state.total),
                style: AppTypography.of(context).body,
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanSummaryBanner extends StatelessWidget {
  const _ScanSummaryBanner({required this.summary, required this.l10n});

  final ExternalScanSummary summary;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: GlassSurface(
        key: const Key('local-center-scan-summary'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: <Widget>[
              const Icon(Icons.check_circle_outline, size: AppSizes.iconMd),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.localCenterScanResult(
                    summary.added,
                    summary.updated,
                    summary.skipped,
                    summary.removed,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
