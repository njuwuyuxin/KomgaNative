import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/providers/local_library_center_provider.dart';
import 'package:yomu_platform/yomu_platform.dart';

/// 本地书库管理中心的单个已挂载外部目录行（LMB-09）。
class LocalMountedRootTile extends StatelessWidget {
  const LocalMountedRootTile({
    required this.row,
    required this.scanning,
    required this.onRescan,
    required this.onEnsureNomedia,
    required this.onUnmount,
    super.key,
  });

  final LocalMountedRootsRow row;
  final bool scanning;
  final VoidCallback onRescan;
  final VoidCallback onEnsureNomedia;
  final VoidCallback onUnmount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kindLabel = switch (row.kind) {
      'androidSaf' => 'SAF',
      'iosBookmark' => 'iOS Files',
      _ => l10n.localCenterKindFolder,
    };
    final nomediaNote = row.hasNomedia ? ' · .nomedia' : '';
    return ListTile(
      key: Key('mounted-root-${row.id}'),
      leading: const Icon(Icons.folder_outlined),
      title: Text(
        row.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${l10n.localCenterRootSubtitle(kindLabel, row.booksCount)}$nomediaNote',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!row.hasNomedia && row.kind != ExternalRootKind.iosBookmark.name)
            IconButton(
              key: Key('root-nomedia-${row.id}'),
              tooltip: l10n.localCenterCreateNomedia,
              icon: const Icon(Icons.hide_image_outlined),
              onPressed: scanning ? null : onEnsureNomedia,
            ),
          IconButton(
            key: Key('root-rescan-${row.id}'),
            tooltip: l10n.localCenterRescanRoot,
            icon: const Icon(Icons.refresh),
            onPressed: scanning ? null : onRescan,
          ),
          IconButton(
            key: Key('root-unmount-${row.id}'),
            tooltip: l10n.localCenterUnmountRoot,
            icon: const Icon(Icons.link_off),
            onPressed: scanning ? null : onUnmount,
          ),
        ],
      ),
    );
  }
}

/// 弹出确认对话框安全卸载外部目录（绝不删除原始外部文件）。
Future<void> confirmUnmountExternalRoot(
  BuildContext context,
  WidgetRef ref,
  LocalMountedRootsRow row,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(l10n.localCenterUnmountTitle),
      content: Text(l10n.localCenterUnmountBody(row.displayName)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('confirm-unmount-root'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.localCenterUnmountRoot),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(localLibraryScanProvider.notifier).unmountRoot(row);
  }
}
