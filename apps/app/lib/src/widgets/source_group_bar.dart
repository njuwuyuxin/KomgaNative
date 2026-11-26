import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/local_import_provider.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 多源书架分组与本机导入工具行：
/// - 单源且本机书架为空时隐藏（中心空态引导卡已有主导入按钮，顶栏不重复堆叠，保留完整搜索框宽度）；
/// - 多源时展示 `[ 本机 ]` / `[ ☁ 服务器 ]` 胶囊；处于本机分组且已有书籍时右侧提供 `+ 导入` 菜单。
class SourceGroupBar extends ConsumerWidget {
  const SourceGroupBar({this.showLocalImport = false, super.key});

  final bool showLocalImport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(availableSourcesProvider);
    final isWide =
        WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.expanded;
    final showSourceChips = sources.length > 1 && !isWide;
    if (!showSourceChips && !showLocalImport) {
      return const SizedBox.shrink();
    }

    final active = ref.watch(activeSourceProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SizedBox(
      key: showSourceChips ? const Key('source-group-bar') : null,
      height: AppSizes.minTouch - AppSpacing.xs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: <Widget>[
            if (showSourceChips)
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
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
                          : const Icon(
                              Icons.smartphone_outlined,
                              size: AppSizes.iconXs,
                            ),
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
              )
            else
              const Spacer(),
            if (showLocalImport) ...<Widget>[
              if (showSourceChips) const SizedBox(width: AppSpacing.xs),
              const LocalImportMenuOrb(),
            ],
          ],
        ),
      ),
    );
  }
}

/// 本机书库「+ 导入漫画」紧凑玻璃菜单按钮。
class LocalImportMenuOrb extends ConsumerWidget {
  const LocalImportMenuOrb({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final busy = ref.watch(localImportProvider.select((s) => s.busy));

    return GlassMenuButton(
      key: const Key('shelf-import-orb'),
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
    final first = result.failures.first;
    text = first.reason == ImportFailureReason.textOnlyEpub
        ? l10n.importFailedTextOnlyEpub(first.fileName)
        : l10n.importFailedUnsupported(first.fileName);
  } else {
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
