import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/cache/http_cache_database.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/download_providers.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/reader_args.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu/src/widgets/download_queue_menu.dart';
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
      body: GlassPageBackground(
        child: RefreshIndicator(
          edgeOffset:
              MediaQuery.paddingOf(context).top + AppSizes.glassHeaderClearance,
          onRefresh: () async {
            ref.invalidate(downloadedBooksProvider);
            ref.invalidate(downloadsUsageProvider);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              GlassHeaderSliver(
                // UI-01：整条标题栏只有**一层**玻璃——返回、标题、"取消全部"
                // 全在同一个胶囊里，不再是"圆球 + 胶囊 + 圆球"三件套。
                header: GlassHeader(
                  bar: GlassSurface(
                    shape: AppShapes.of(context, AppShapes.bar),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          key: const Key('downloads-back'),
                          tooltip: MaterialLocalizations.of(context)
                              .backButtonTooltip,
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              context.pop();
                            }
                          },
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            l10n.downloadedBooks,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.of(context).title,
                          ),
                        ),
                        // 队列动作收进一个菜单（DLD-02）：暂停/继续、重试失败、
                        // 取消全部、删除全部——四个按钮平铺会把标题挤没。
                        if (active.isNotEmpty || ids.isNotEmpty)
                          QueueMenu(
                            paused: ref.read(downloadsProvider.notifier).paused,
                            hasActive: active.isNotEmpty,
                            hasFailed: active.values.any(
                              (DownloadStatus s) => s.hasError,
                            ),
                            hasRecords: records.value?.isNotEmpty ?? false,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (ids.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.download_outlined,
                        size: AppSpacing.xxl,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(l10n.downloadsEmpty),
                      const SizedBox(height: AppSpacing.xs),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                        ),
                        child: Text(
                          l10n.downloadsEmptyHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSizes.navBarClearance,
                  ),
                  sliver: SliverList.list(
                    children: <Widget>[
                      AppListGroup(
                        key: const Key('downloads-list'),
                        children: <Widget>[
                          for (final id in ids) _DownloadRow(bookId: id),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
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
    final controller = ref.read(downloadsProvider.notifier);
    final known = controller.knownBook(bookId);
    final cover = ref
        .watch(bookCoverProvider((sourceKey: book?.sourceKey, id: bookId)))
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

    return ListTile(
      key: Key('download-$bookId'),
      onTap: openRecord != null
          ? () => unawaited(
              context.push(
                '/reader/$bookId',
                extra: ReaderArgs(
                  book:
                      book ??
                      Book(
                        id: openRecord.bookId,
                        seriesId: openRecord.seriesId,
                        name: title,
                        pagesCount: openRecord.pageCount,
                      ),
                ),
              ),
            )
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
            // 进度数字用等宽字形：否则 "9 / 12" → "10 / 12" 会让整行左右抖。
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
                    controller.retryOne(bookId, fallback: book ?? known),
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
              onPressed: () => _delete(context, ref, book, record),
              icon: const Icon(Icons.delete_outline),
            ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Book? book,
    DownloadedBook? record,
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
    await ref
        .read(downloadsProvider.notifier)
        .delete(
          book ??
              Book(
                id: bookId,
                seriesId: record?.seriesId ?? '',
                name: record?.bookName ?? bookId,
                pagesCount: record?.pageCount ?? 0,
              ),
        );
  }
}

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
