import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:material_ui/material_ui.dart';

/// 连接页上的"已保存服务器"快捷切换卡片（从设置页点"添加服务器"进入时可随时一键切回）。
class SavedServersCard extends StatelessWidget {
  const SavedServersCard({
    required this.servers,
    required this.enabled,
    required this.onSelect,
    super.key,
  });

  final List<StoredServer> servers;
  final bool enabled;
  final ValueChanged<StoredServer> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppListGroup(
      key: const Key('connection-saved-servers'),
      header: l10n.savedServers,
      children: <Widget>[
        for (final server in servers)
          ListTile(
            key: Key('connection-saved-${server.id}'),
            enabled: enabled,
            leading: const Icon(Icons.dns_outlined),
            title: Text(
              server.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              server.address.baseUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onSelect(server),
          ),
      ],
    );
  }
}
