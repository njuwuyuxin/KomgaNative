import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/widgets/local_metadata_sheets.dart';
import 'package:yomu/src/widgets/series_download_menu.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 系列详情页的悬浮毛玻璃顶栏（收藏、整系列下载、编辑元数据与已读/未读菜单）。
PreferredSizeWidget buildSeriesDetailAppBar(
  BuildContext context,
  WidgetRef ref, {
  required String seriesId,
  required Series? series,
  required List<Book> books,
  required bool inCollection,
  required Future<void> Function() onOpenCollectionsPicker,
  required Future<void> Function({required bool read}) onMarkSeriesRead,
}) {
  final l10n = AppLocalizations.of(context);
  return GlassTopBar(
    header: GlassHeader(
      leading: GlassIconButton(
        icon: Icons.chevron_left,
        label: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => context.pop(),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          GlassIconButton(
            key: const Key('series-collection-button'),
            icon: inCollection
                ? Icons.collections_bookmark
                : Icons.collections_bookmark_outlined,
            label: l10n.addToCollection,
            onPressed: () => unawaited(onOpenCollectionsPicker()),
          ),
          if (!seriesId.startsWith('local:')) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            SeriesDownloadMenu(seriesId: seriesId, books: books),
          ],
          const SizedBox(width: AppSpacing.sm),
          GlassMenuButton(
            key: const Key('series-mark-menu'),
            orb: true,
            icon: Icons.more_horiz,
            label: l10n.moreActions,
            menuChildren: <Widget>[
              if (series != null && seriesId.startsWith('local:'))
                GlassMenuItemButton(
                  key: const Key('series-edit-metadata'),
                  label: l10n.editMetadata,
                  onPressed: () =>
                      unawaited(showEditLocalSeriesSheet(context, ref, series)),
                ),
              GlassMenuItemButton(
                key: const Key('series-add-to-collection'),
                label: l10n.addToCollection,
                onPressed: () => unawaited(onOpenCollectionsPicker()),
              ),
              GlassMenuItemButton(
                key: const Key('series-mark-read'),
                label: l10n.markAllRead,
                onPressed: () => unawaited(onMarkSeriesRead(read: true)),
              ),
              GlassMenuItemButton(
                key: const Key('series-mark-unread'),
                label: l10n.markAllUnread,
                onPressed: () => unawaited(onMarkSeriesRead(read: false)),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
