import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/l10n/failure_text.dart';
import 'package:komga_native/src/providers/pinned_series_provider.dart';
import 'package:komga_native/src/providers/series_read_provider.dart';
import 'package:komga_native/src/screens/series_detail_args.dart';
import 'package:komga_native/src/widgets/context_menu.dart';
import 'package:material_ui/material_ui.dart';

/// 长按系列卡片能做的事（UI-P2-5）。
enum SeriesMenuAction { markRead, markUnread, viewDetails, pin, unpin }

/// 长按系列的上下文菜单（UI-P2-5 / ARC-05 / ARC-12 独立文件），网格卡片与列表行共用。
Future<void> showSeriesMenu(
  BuildContext context,
  WidgetRef ref,
  Series series, {
  String? heroTag,
  bool pinned = false,
}) async {
  final l10n = AppLocalizations.of(context);
  unawaited(AppHaptics.light());
  final action = await showContextMenu<SeriesMenuAction>(
    context: context,
    anchor: context,
    entries: <ContextMenuEntry<SeriesMenuAction>>[
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
    ],
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  switch (action) {
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
  }
}
