import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/download_policy_gate.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:material_ui/material_ui.dart';

/// 一本书的下载按钮：未下载 / 下载中（可取消）/ 已下载（可删除）。
///
/// 单独成文件：系列详情已经很长，而"下载状态 → 图标"的映射还要在阅读器复用。
class BookDownloadButton extends ConsumerWidget {
  const BookDownloadButton({required this.book, super.key});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = ref.watch(downloadsProvider)[book.id];
    final downloaded = ref.watch(downloadedProvider(book.id)).value;
    final controller = ref.read(downloadsProvider.notifier);

    if (status?.isRunning ?? false) {
      final progress = status!.progress!;
      return IconButton(
        key: Key('book-download-${book.id}'),
        tooltip: l10n.cancelDownload,
        onPressed: () => controller.cancel(book.id),
        icon: SizedBox(
          width: AppSizes.iconMd,
          height: AppSizes.iconMd,
          child: CircularProgressIndicator(
            value: progress.fraction,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final errorKind = status?.errorKind;
    if (errorKind != null) {
      return IconButton(
        key: Key('book-download-${book.id}'),
        tooltip: l10n.downloadRetryTooltip(l10n.failureTitle(errorKind)),
        onPressed: () {
          controller.dismiss(book.id);
          unawaited(controller.start(book));
        },
        icon: Icon(Icons.error_outline, color: theme.colorScheme.error),
      );
    }

    if (downloaded != null) {
      return IconButton(
        key: Key('book-download-${book.id}'),
        tooltip: l10n.downloadedTapToRemove,
        onPressed: () => _confirmDelete(context, controller),
        icon: Icon(Icons.download_done, color: theme.colorScheme.primary),
      );
    }

    return IconButton(
      key: Key('book-download-${book.id}'),
      tooltip: l10n.downloadForOffline,
      onPressed: () => unawaited(_start(ref, context, l10n, controller, book)),
      icon: const Icon(Icons.download_outlined),
    );
  }

  /// 开始下载前先过一遍"仅 Wi-Fi"策略（DLD-01）。
  Future<void> _start(
    WidgetRef ref,
    BuildContext context,
    AppLocalizations l10n,
    DownloadsController controller,
    Book book,
  ) async {
    final blocked = await downloadBlockReason(ref, l10n);
    if (blocked != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    await controller.start(book);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    DownloadsController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.removeDownloadTitle),
          content: Text(l10n.removeDownloadBody),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.remove),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) await controller.delete(book);
  }
}
