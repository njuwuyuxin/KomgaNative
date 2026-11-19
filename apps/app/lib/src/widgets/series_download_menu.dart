import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 系列页的"下载"菜单（SER-03）：全部 / 未读前 N 本。
///
/// 先弹确认框再入队：一次可能排进几十本，误触的代价是几百兆流量。
/// 确认框里会写清"将下载 N 本、跳过已下载 M 本"，用户才知道点下去发生什么。
class SeriesDownloadMenu extends ConsumerWidget {
  const SeriesDownloadMenu({
    required this.seriesId,
    required this.books,
    super.key,
  });

  final String seriesId;

  /// 当前已加载的书（按当前排序/筛选）。服务端分页，这里只对已加载的负责。
  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // 未读 = 没读完的（含没开始读的）；"下载未读 N 本"按当前顺序取前面的。
    final unread = <Book>[
      for (final book in books)
        if (!book.isCompleted) book,
    ];
    return GlassMenuButton(
      key: const Key('series-download-menu'),
      orb: true,
      icon: Icons.download_outlined,
      label: l10n.downloadSeries,
      menuChildren: <Widget>[
        GlassMenuItemButton(
          key: const Key('series-download-all'),
          label: l10n.downloadAll,
          onPressed: () => unawaited(_confirmAndStart(context, ref, books)),
        ),
        for (final count in <int>[1, 5, 10])
          GlassMenuItemButton(
            key: Key('series-download-unread-$count'),
            label: l10n.downloadUnreadCount(count),
            enabled: unread.isNotEmpty,
            onPressed: () => unawaited(
              _confirmAndStart(context, ref, unread.take(count).toList()),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmAndStart(
    BuildContext context,
    WidgetRef ref,
    List<Book> targets,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (targets.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('series-download-confirm'),
        title: Text(l10n.downloadConfirmTitle(targets.length)),
        content: Text(l10n.downloadConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('series-download-confirm-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.download),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ids = <String>[for (final book in targets) book.id];
    final result = await ref
        .read(downloadsProvider.notifier)
        .startMany(targets);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.skipped == 0
              ? l10n.downloadBatchQueued(result.queued)
              : l10n.downloadQueuedSkipped(result.queued, result.skipped),
        ),
        duration: const Duration(seconds: 6),
        action: result.queued == 0
            ? null
            : SnackBarAction(
                label: l10n.cancel,
                onPressed: () =>
                    ref.read(downloadsProvider.notifier).cancelMany(ids),
              ),
      ),
    );
  }
}
