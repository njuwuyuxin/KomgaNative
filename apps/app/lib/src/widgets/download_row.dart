import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/reader_args.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 下载管理页单行：展示进度、错误重试或已下载打开/删除操作。
class DownloadRow extends ConsumerWidget {
  const DownloadRow({required this.bookId, super.key});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final records = ref.watch(downloadedBooksProvider).value;
    DownloadedBookRecord? record;
    for (final DownloadedBookRecord item
        in records ?? const <DownloadedBookRecord>[]) {
      if (item.bookId == bookId) {
        record = item;
        break;
      }
    }
    final status = ref.watch(downloadsProvider)[bookId];
    final controller = ref.read(downloadsProvider.notifier);
    final known = controller.knownBook(bookId);
    final downloadScope = ref.watch(downloadScopeProvider);
    final rowSourceKey = (record != null && record.scope.isNotEmpty)
        ? record.scope
        : (known != null && known.isCloud)
        ? known.sourceKey
        : (downloadScope.isNotEmpty ? downloadScope : null);
    final book = ref
        .watch(bookByIdProvider((sourceKey: rowSourceKey, bookId: bookId)))
        .value;
    final coverSourceKey = (book != null && book.isCloud)
        ? book.sourceKey
        : rowSourceKey;
    final cover = ref
        .watch(bookCoverProvider((sourceKey: coverSourceKey, id: bookId)))
        .value;

    final title =
        book?.name ??
        known?.name ??
        ((record?.bookName.isNotEmpty ?? false) ? record!.bookName : bookId);
    final isRunning = status?.isRunning ?? false;
    final isQueued = status?.queued ?? false;
    final errorKind = status?.errorKind;
    final subtitle = isRunning
        ? '${status!.progress!.done} / ${status.progress!.total}'
        : isQueued
        ? l10n.downloadQueued
        : errorKind != null
        ? l10n.failureTitle(errorKind)
        : record == null
        ? l10n.downloadsEmpty
        : l10n.downloadPagesBytes(record.pageCount, _humanBytes(record.bytes));

    final openRecord = (!isRunning && !isQueued && errorKind == null)
        ? record
        : null;
    final openSourceKey = (openRecord != null && openRecord.scope.isNotEmpty)
        ? openRecord.scope
        : (rowSourceKey ?? '');

    return ListTile(
      key: Key('download-$bookId'),
      onTap: openRecord != null && openSourceKey.isNotEmpty
          ? () {
              final openBook = (book != null && book.sourceKey == openSourceKey)
                  ? book
                  : (book?.withSource(openSourceKey) ??
                        Book(
                          id: openRecord.bookId,
                          seriesId: openRecord.seriesId,
                          name: title,
                          pagesCount: openRecord.pageCount,
                          sourceKey: openSourceKey,
                        ));
              final uri = Uri(
                path: '/reader/$bookId',
                queryParameters: <String, String>{'source': openSourceKey},
              );
              unawaited(
                context.push(
                  uri.toString(),
                  extra: ReaderArgs(book: openBook, sourceKey: openSourceKey),
                ),
              );
            }
          : null,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xs),
        child: SizedBox(
          width: AppSizes.rowCover.width,
          height: AppSizes.rowCover.height,
          child: cover == null
              ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
              : CoverImage(bytes: cover),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            subtitle,
            style: isRunning
                ? AppTypography.of(context).progressNumber
                : errorKind != null
                ? theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  )
                : null,
          ),
          if (isRunning) ...<Widget>[
            const SizedBox(height: AppSpacing.xxs),
            LinearProgressIndicator(
              value: status!.progress!.fraction,
              minHeight: AppSizes.progressBar,
            ),
          ],
        ],
      ),
      trailing: isRunning || isQueued
          ? IconButton(
              tooltip: l10n.cancelDownload,
              onPressed: () => controller.cancel(bookId),
              icon: const Icon(Icons.close),
            )
          : errorKind != null
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  key: Key('download-retry-$bookId'),
                  tooltip: l10n.retry,
                  onPressed: () => unawaited(
                    controller.retryOne(
                      bookId,
                      fallback: book ?? known,
                      sourceKey: rowSourceKey,
                    ),
                  ),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  key: Key('download-dismiss-$bookId'),
                  tooltip: l10n.cancelDownload,
                  onPressed: () => controller.dismiss(bookId),
                  icon: const Icon(Icons.close),
                ),
              ],
            )
          : IconButton(
              tooltip: l10n.downloadedTapToRemove,
              onPressed: () =>
                  _delete(context, ref, book, record, rowSourceKey),
              icon: const Icon(Icons.delete_outline),
            ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Book? book,
    DownloadedBookRecord? record,
    String? sourceKey,
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
    if (confirmed != true) return;
    final deleteSourceKey = (record != null && record.scope.isNotEmpty)
        ? record.scope
        : (sourceKey ?? kLocalSourceKey);
    await ref
        .read(downloadsProvider.notifier)
        .delete(
          book ??
              Book(
                id: bookId,
                seriesId: record?.seriesId ?? '',
                name: record?.bookName ?? bookId,
                pagesCount: record?.pageCount ?? 0,
                sourceKey: deleteSourceKey,
              ),
        );
  }
}

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
