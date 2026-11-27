import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 下载页标题栏右侧的队列动作菜单（DLD-02）。
///
/// 为什么收进菜单：暂停/继续、重试失败、取消全部、删除全部是四个低频动作，
/// 平铺成四个图标会把标题挤没；而"取消全部"和"删除全部"都不可撤销，
/// 放到菜单里还能顺手加一句说明。
class QueueMenu extends ConsumerWidget {
  const QueueMenu({
    required this.paused,
    required this.hasActive,
    required this.hasFailed,
    required this.hasRecords,
    super.key,
  });

  final bool paused;
  final bool hasActive;
  final bool hasFailed;
  final bool hasRecords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(downloadsProvider.notifier);
    return GlassMenuButton(
      key: const Key('downloads-menu'),
      orb: true,
      icon: Icons.more_vert,
      label: l10n.readerMore,
      menuChildren: <Widget>[
        if (hasActive)
          GlassMenuItemButton(
            key: const Key('downloads-toggle-pause'),
            label: paused ? l10n.downloadResumeAll : l10n.downloadPauseAll,
            icon: paused ? Icons.play_arrow : Icons.pause,
            onPressed: () =>
                paused ? controller.resumeAll() : controller.pauseAll(),
          ),
        if (hasFailed)
          GlassMenuItemButton(
            key: const Key('downloads-retry-failed'),
            label: l10n.downloadRetryFailed,
            icon: Icons.refresh,
            onPressed: () => unawaited(controller.retryFailed()),
          ),
        if (hasActive)
          GlassMenuItemButton(
            key: const Key('downloads-cancel-all'),
            label: l10n.downloadCancelAll,
            icon: Icons.stop_circle_outlined,
            onPressed: controller.cancelAll,
          ),
        if (hasRecords)
          GlassMenuItemButton(
            key: const Key('downloads-delete-all'),
            label: l10n.downloadDeleteAll,
            icon: Icons.delete_sweep_outlined,
            onPressed: () => unawaited(_confirmDeleteAll(context, ref, l10n)),
          ),
      ],
    );
  }

  /// 删除全部已下载：不可撤销，所以先确认。
  Future<void> _confirmDeleteAll(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('downloads-delete-all-confirm'),
        title: Text(l10n.downloadDeleteAllTitle),
        content: Text(l10n.downloadDeleteAllBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('downloads-delete-all-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final records = ref.read(downloadedBooksProvider).value ?? const [];
    final controller = ref.read(downloadsProvider.notifier);
    for (final record in records) {
      await controller.delete(
        Book(
          id: record.bookId,
          seriesId: record.seriesId,
          name: record.bookName.isEmpty ? record.bookId : record.bookName,
          pagesCount: record.pageCount,
          sourceKey: record.scope.isNotEmpty ? record.scope : kLocalSourceKey,
        ),
      );
    }
  }
}
