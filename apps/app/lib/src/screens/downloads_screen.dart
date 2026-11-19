import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/cache/http_cache_database.dart';
import 'package:komga_native/src/providers/download_providers.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 下载管理页（UI-P3-13）：进行中 / 排队 / 已下载，可取消、删除。
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final records = ref.watch(downloadedBooksProvider);
    final active = ref.watch(downloadsProvider);
    final ids = <String>{
      ...?records.value?.map((DownloadedBook r) => r.bookId),
      ...active.keys,
    }.toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.downloadedBooks)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(downloadedBooksProvider);
          ref.invalidate(downloadsUsageProvider);
        },
        child: ids.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: <Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  Icon(
                    Icons.download_outlined,
                    size: AppSpacing.xxl,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(child: Text(l10n.downloadsEmpty)),
                ],
              )
            : ListView.separated(
                key: const Key('downloads-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: ids.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: AppSizes.hairline),
                itemBuilder: (BuildContext context, int index) =>
                    _DownloadRow(bookId: ids.elementAt(index)),
              ),
      ),
    );
  }
}

class _DownloadRow extends ConsumerWidget {
  const _DownloadRow({required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = ref.watch(bookByIdProvider(bookId)).value;
    final records = ref.watch(downloadedBooksProvider).value;
    DownloadedBook? record;
    for (final DownloadedBook item in records ?? const <DownloadedBook>[]) {
      if (item.bookId == bookId) {
        record = item;
        break;
      }
    }
    final status = ref.watch(downloadsProvider)[bookId];
    final cover = ref.watch(bookCoverProvider(bookId)).value;

    final title = book?.name ?? bookId;
    final subtitle = status?.isRunning ?? false
        ? '${status!.progress!.done} / ${status.progress!.total}'
        : status?.queued ?? false
        ? l10n.downloadQueued
        : record == null
        ? l10n.downloadsEmpty
        : l10n.downloadPagesBytes(record.pageCount, _humanBytes(record.bytes));

    return ListTile(
      key: Key('download-$bookId'),
      leading: SizedBox(
        width: AppSizes.rowCover.width,
        height: AppSizes.rowCover.height,
        child: cover == null
            ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
            : CoverImage(bytes: cover),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(subtitle),
          if (status?.isRunning ?? false) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            LinearProgressIndicator(
              value: status!.progress!.fraction,
              minHeight: AppSizes.progressBar,
            ),
          ],
        ],
      ),
      trailing: (status?.isRunning ?? false) || (status?.queued ?? false)
          ? IconButton(
              tooltip: l10n.cancelDownload,
              onPressed: () =>
                  ref.read(downloadsProvider.notifier).cancel(bookId),
              icon: const Icon(Icons.close),
            )
          : IconButton(
              tooltip: l10n.downloadedTapToRemove,
              onPressed: () => _delete(context, ref, book),
              icon: const Icon(Icons.delete_outline),
            ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Book? book) async {
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
    if (confirmed != true) return;
    await ref
        .read(downloadsProvider.notifier)
        .delete(
          book ?? Book(id: bookId, seriesId: '', name: bookId, pagesCount: 0),
        );
    ref.invalidate(downloadedBooksProvider);
  }
}

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
