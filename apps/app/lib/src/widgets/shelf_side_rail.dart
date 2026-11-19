import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 平板书架左侧的"库"导航（PLT-01）。
///
/// 只在 `WindowSizeClass.expanded`（≥1024）出现：手机上这一栏会把封面挤到两列，
/// 反而更难用。选中项直接驱动 `ShelfController.selectLibrary`，
/// 与搜索框旁边那个库筛选菜单是同一份状态。
class ShelfSideRail extends ConsumerWidget {
  const ShelfSideRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final libraries = ref.watch(librariesProvider).value ?? const <Library>[];
    final shelf = ref.watch(shelfProvider);
    final controller = ref.read(shelfProvider.notifier);
    final theme = Theme.of(context);

    return Container(
      key: const Key('shelf-side-rail'),
      width: AppSizes.sideRailWidth,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSizes.navBarClearance,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              l10n.libraries,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _RailTile(
            key: const Key('side-rail-all'),
            icon: Icons.auto_stories_outlined,
            label: l10n.allSeries,
            selected: shelf.libraryId == null,
            onTap: () => controller.selectLibrary(null),
          ),
          for (final library in libraries)
            _RailTile(
              key: Key('side-rail-${library.id}'),
              icon: Icons.collections_bookmark_outlined,
              label: library.name,
              selected: shelf.libraryId == library.id,
              onTap: () => controller.selectLibrary(library.id),
            ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      leading: Icon(icon, size: AppSizes.iconSm),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}
