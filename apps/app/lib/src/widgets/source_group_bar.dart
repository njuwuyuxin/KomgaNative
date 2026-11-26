import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 多源书架/收藏分组切换条（ADR 0008 不变量 2）：
/// - **单源隐形**：当系统仅存在「本机」单一源（未添加任何服务器）时，返回 `SizedBox.shrink()` 零占位；
/// - **多源清晰分组**：当已配置远程服务器时，渲染 `[ 本机 ]` 与各台 `[ ☁ 服务器 ]` 分组胶囊。
class SourceGroupBar extends ConsumerWidget {
  const SourceGroupBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(availableSourcesProvider);
    if (sources.length <= 1) return const SizedBox.shrink();

    final active = ref.watch(activeSourceProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SizedBox(
      key: const Key('source-group-bar'),
      height: AppSizes.minTouch - AppSpacing.xs,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: sources.length,
        separatorBuilder: (BuildContext _, int _) =>
            const SizedBox(width: AppSpacing.xs),
        itemBuilder: (BuildContext context, int index) {
          final item = sources[index];
          final selected = item.sourceKey == active.sourceKey;
          final label = switch (item) {
            LocalContentSource() => l10n.localLibrary,
            RemoteContentSource(:final displayName) => displayName,
          };
          return ChoiceChip(
            key: Key('source-chip-${item.sourceKey}'),
            avatar: item.isCloud
                ? Icon(
                    Icons.cloud_outlined,
                    size: AppSizes.iconXs,
                    color: selected
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  )
                : const Icon(Icons.smartphone_outlined, size: AppSizes.iconXs),
            label: Text(label),
            selected: selected,
            onSelected: (bool value) {
              if (!value || selected) return;
              unawaited(AppHaptics.selection());
              unawaited(
                ref
                    .read(activeSourceProvider.notifier)
                    .selectSource(item.sourceKey),
              );
            },
          );
        },
      ),
    );
  }
}

/// 本机书库顶栏「+ 导入漫画」玻璃圆球菜单按钮。
class LocalImportMenuOrb extends ConsumerWidget {
  const LocalImportMenuOrb({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final busy = ref.watch(localImportProvider.select((s) => s.busy));

    return GlassMenuButton(
      key: const Key('shelf-import-orb'),
      orb: true,
      icon: busy ? Icons.hourglass_top : Icons.add,
      label: l10n.importComics,
      menuChildren: <Widget>[
        GlassMenuItemButton(
          key: const Key('import-menu-files'),
          icon: Icons.folder_zip_outlined,
          label: l10n.importArchiveFiles,
          onPressed: () {
            if (!busy) unawaited(runLocalArchiveImport(context, ref));
          },
        ),
        GlassMenuItemButton(
          key: const Key('import-menu-folder'),
          icon: Icons.create_new_folder_outlined,
          label: l10n.importComicFolder,
          onPressed: () {
            if (!busy) unawaited(runLocalFolderImport(context, ref));
          },
        ),
      ],
    );
  }
}

/// 导入进行中的轻量进度横条（不弹阻塞模态框，用户可继续浏览已有书架）。
class LocalImportProgressBanner extends ConsumerWidget {
  const LocalImportProgressBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(localImportProvider);
    if (!importState.busy) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: GlassSurface(
        key: const Key('local-import-progress'),
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: <Widget>[
              const SizedBox(
                width: AppSizes.iconXs,
                height: AppSizes.iconXs,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.importingProgress(
                    importState.completed,
                    importState.total,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> runLocalArchiveImport(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  final result = await ref
      .read(localImportProvider.notifier)
      .pickAndImportArchives();
  if (result == null) return;
  _showImportOutcome(messenger, l10n, result);
}

Future<void> runLocalFolderImport(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  final result = await ref
      .read(localImportProvider.notifier)
      .pickAndImportDirectory();
  if (result == null) return;
  _showImportOutcome(messenger, l10n, result);
}

void _showImportOutcome(
  ScaffoldMessengerState? messenger,
  AppLocalizations l10n,
  LocalImportBatchResult result,
) {
  if (messenger == null) return;
  final String text;
  if (result.importedCount > 0 && !result.hasFailures) {
    text = l10n.importSucceeded(result.importedCount);
  } else if (result.importedCount > 0 && result.hasFailures) {
    text = l10n.importPartialResult(
      result.importedCount,
      result.failures.length,
    );
  } else if (result.hasFailures) {
    text = l10n.importFailedUnsupported(result.failures.first.fileName);
  } else {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
