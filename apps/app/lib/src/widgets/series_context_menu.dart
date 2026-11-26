import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/local_catalog_mutator_provider.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/series_read_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/screens/series_detail_args.dart';
import 'package:yomu/src/widgets/collection_picker_sheet.dart';
import 'package:yomu/src/widgets/context_menu.dart';
import 'package:yomu/src/widgets/local_metadata_sheets.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:material_ui/material_ui.dart';

/// 长按系列卡片能做的事（UI-P2-5）。
enum SeriesMenuAction {
  removeFromCollection,
  addToCollection,
  markRead,
  markUnread,
  viewDetails,
  pin,
  unpin,
  editMetadata,
  deleteFromDevice,
}

/// 长按系列的上下文菜单（UI-P2-5 / ARC-05 / ARC-12 独立文件），网格卡片与列表行共用。
Future<void> showSeriesMenu(
  BuildContext context,
  WidgetRef ref,
  Series series, {
  String? heroTag,
  bool pinned = false,
  Future<void> Function()? onRemoveFromCollection,
}) async {
  final l10n = AppLocalizations.of(context);
  final caps = ref.read(
    sourceCapabilitiesForItemProvider((
      scopedSourceKey: ScopedSourceScope.readOf(context),
      entitySourceKey: series.sourceKey,
    )),
  );
  unawaited(AppHaptics.light());
  final action = await showContextMenu<SeriesMenuAction>(
    context: context,
    anchor: context,
    entries: <ContextMenuEntry<SeriesMenuAction>>[
      if (onRemoveFromCollection != null)
        ContextMenuEntry(
          value: SeriesMenuAction.removeFromCollection,
          label: l10n.removeFromCollection,
          icon: Icons.remove_circle_outline,
        ),
      ContextMenuEntry(
        value: SeriesMenuAction.addToCollection,
        label: l10n.addToCollection,
        icon: Icons.collections_bookmark_outlined,
      ),
      ContextMenuEntry(
        value: SeriesMenuAction.markRead,
        label: l10n.markAllRead,
        icon: Icons.done_all,
      ),
      ContextMenuEntry(
        value: SeriesMenuAction.markUnread,
        label: l10n.markAllUnread,
        icon: Icons.remove_done,
      ),
      if (pinned)
        ContextMenuEntry(
          value: SeriesMenuAction.unpin,
          label: l10n.unpinSeries,
          icon: Icons.push_pin_outlined,
        )
      else
        ContextMenuEntry(
          value: SeriesMenuAction.pin,
          label: l10n.pinSeries,
          icon: Icons.push_pin,
        ),
      ContextMenuEntry(
        value: SeriesMenuAction.viewDetails,
        label: l10n.viewDetails,
        icon: Icons.info_outline,
      ),
      if (caps.canMutateCatalog) ...<ContextMenuEntry<SeriesMenuAction>>[
        ContextMenuEntry(
          value: SeriesMenuAction.editMetadata,
          label: l10n.editMetadata,
          icon: Icons.edit_outlined,
        ),
        ContextMenuEntry(
          value: SeriesMenuAction.deleteFromDevice,
          label: l10n.deleteFromDevice,
          icon: Icons.delete_outline,
        ),
      ],
    ],
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  switch (action) {
    case SeriesMenuAction.removeFromCollection:
      await onRemoveFromCollection?.call();
    case SeriesMenuAction.addToCollection:
      await showCollectionPickerSheet(context, seriesIds: <String>[series.id]);
    case SeriesMenuAction.viewDetails:
      await context.push(
        '/series/${series.id}',
        extra: SeriesDetailArgs(heroTag: heroTag),
      );
    case SeriesMenuAction.markRead:
    case SeriesMenuAction.markUnread:
      try {
        await ref
            .read(seriesReadProvider.notifier)
            .setRead(series.id, read: action == SeriesMenuAction.markRead);
      } on ShelfFailure catch (failure) {
        messenger?.showSnackBar(
          SnackBar(content: Text(l10n.failureTitle(failure.kind))),
        );
      }
    case SeriesMenuAction.pin:
      await ref
          .read(pinnedSeriesControllerProvider)
          .toggle(series.id, pinned: true);
    case SeriesMenuAction.unpin:
      await ref
          .read(pinnedSeriesControllerProvider)
          .toggle(series.id, pinned: false);
    case SeriesMenuAction.editMetadata:
      await showEditLocalSeriesSheet(context, ref, series);
    case SeriesMenuAction.deleteFromDevice:
      final confirmed = await confirmDeleteLocalItems(context, count: 1);
      if (!confirmed) return;
      await ref.read(localCatalogMutatorProvider).deleteSeries(<String>[
        series.id,
      ]);
  }
}
