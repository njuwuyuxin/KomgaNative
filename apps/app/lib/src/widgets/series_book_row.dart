import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/book_read_provider.dart';
import 'package:yomu/src/providers/download_policy_gate.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/local_catalog_mutator_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/widgets/book_download_button.dart';
import 'package:yomu/src/widgets/context_menu.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu/src/widgets/local_metadata_sheets.dart';
import 'package:yomu/src/widgets/readlist_picker_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// 一本书：封图 + 标题 + 页数/已读状态，点进去读。
///
/// 整行是一个按钮；读屏只播报「标题 + 页数/已读」，下载按钮仍是独立控件。
class SeriesBookRow extends ConsumerWidget {
  const SeriesBookRow({
    required this.book,
    required this.onOpen,
    this.showSeriesTitle = false,
    this.selected = false,
    this.onToggleSelect,
    this.onMarkPrevious,
    this.onRemoveFromReadList,
    this.trailingAction,
    super.key,
  });

  final Book book;
  final Future<void> Function() onOpen;

  /// 多选模式下这一行是否被勾中。
  final bool selected;

  /// 多选模式下点击这一行：勾选/取消，而不是打开书。
  final VoidCallback? onToggleSelect;

  /// 长按菜单里"标记之前所有为已读/未读"（SER-02）。为空时不显示这两项。
  final Future<void> Function({required bool read})? onMarkPrevious;

  /// 在阅读列表详情页中，长按菜单顶部提供「从阅读列表移出」。
  final Future<void> Function()? onRemoveFromReadList;

  /// 行尾附加动作（例如阅读列表详情页里的移出按钮）。
  final Widget? trailingAction;

  /// 搜索结果里书是**脱离系列**出现的：标题前要补系列名，
  /// 否则一屏都是 "Vol. 1 / Vol. 2"，分不清是哪套书（FIX-06）。
  final bool showSeriesTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scopedSourceKey = ScopedSourceScope.maybeOf(context);
    final sourceKey = scopedSourceKey ?? book.sourceKey;
    final caps = ref.watch(
      sourceCapabilitiesForItemProvider((
        scopedSourceKey: scopedSourceKey,
        entitySourceKey: book.sourceKey,
      )),
    );
    final cover = ref.watch(
      bookCoverProvider((sourceKey: sourceKey, id: book.id)),
    );
    final bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final completed = book.isCompleted;
    final progress = book.readProgress;
    final baseTitle = book.number.isEmpty
        ? book.name
        : '#${book.number} · ${book.name}';
    final seriesTitle = book.seriesTitle;
    final title = showSeriesTitle && seriesTitle != null
        ? '$seriesTitle · ${book.name}'
        : baseTitle;
    // 三档：读完 → "Read · 24 pages"；在读过 → "p. 5/12 · 24 pages"；未读 → "24 pages"。
    final status = completed
        ? l10n.bookReadPages(book.pagesCount)
        : progress == null
        ? l10n.bookPages(book.pagesCount)
        : '${l10n.bookPageProgress(progress.page, book.pagesCount)} · '
              '${l10n.bookPages(book.pagesCount)}';

    return Semantics(
      key: Key('book-${book.id}'),
      container: true,
      button: true,
      label: '$title, $status',
      onTap: () => unawaited(onOpen()),
      child: PressableScale(
        child: ListTile(
          selected: selected,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: SizedBox(
              width: AppSpacing.xl,
              height: AppSpacing.xxl,
              child: bytes == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                    )
                  : CoverImage(bytes: bytes),
            ),
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            status,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (caps.canDownloadOffline) BookDownloadButton(book: book),
              if (trailingAction != null) trailingAction!,
              Icon(
                completed ? Icons.check_circle : Icons.chevron_right,
                color: completed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          onTap: onToggleSelect ?? () => unawaited(onOpen()),
          onLongPress: () => unawaited(_showMenu(context, ref)),
        ),
      ),
    );
  }

  /// 长按一本书：加入/移出阅读列表、标记已读/未读；在系列页还可以"标记之前所有"。
  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final caps = ref.read(
      sourceCapabilitiesForItemProvider((
        scopedSourceKey: ScopedSourceScope.readOf(context),
        entitySourceKey: book.sourceKey,
      )),
    );
    unawaited(AppHaptics.light());
    // 用枚举而不是 bool：单本和"之前所有"是两组不同的动作，
    // 以前两组共用一个 true/false，点"之前所有"会被当成"标记这一本"（踩过）。
    final action = await showContextMenu<BookMenuAction>(
      context: context,
      anchor: context,
      entries: <ContextMenuEntry<BookMenuAction>>[
        if (onRemoveFromReadList != null)
          ContextMenuEntry(
            value: BookMenuAction.removeFromReadList,
            label: l10n.removeFromReadList,
            icon: Icons.playlist_remove,
          ),
        ContextMenuEntry(
          value: BookMenuAction.addToReadList,
          label: l10n.addToReadList,
          icon: Icons.playlist_add,
        ),
        ContextMenuEntry(
          value: BookMenuAction.markRead,
          label: l10n.bookMarkRead,
          icon: Icons.done,
        ),
        ContextMenuEntry(
          value: BookMenuAction.markUnread,
          label: l10n.bookMarkUnread,
          icon: Icons.remove_done,
        ),
        if (onMarkPrevious != null) ...<ContextMenuEntry<BookMenuAction>>[
          ContextMenuEntry(
            value: BookMenuAction.markPreviousRead,
            label: l10n.markPreviousRead,
            icon: Icons.done_all,
          ),
          ContextMenuEntry(
            value: BookMenuAction.markPreviousUnread,
            label: l10n.markPreviousUnread,
            icon: Icons.remove_done,
          ),
        ],
        if (caps.canMutateCatalog) ...<ContextMenuEntry<BookMenuAction>>[
          ContextMenuEntry(
            value: BookMenuAction.editMetadata,
            label: l10n.editMetadata,
            icon: Icons.edit_outlined,
          ),
          ContextMenuEntry(
            value: BookMenuAction.splitSeries,
            label: l10n.splitIntoOwnSeries,
            icon: Icons.call_split,
          ),
          ContextMenuEntry(
            value: BookMenuAction.deleteFromDevice,
            label: l10n.deleteFromDevice,
            icon: Icons.delete_outline,
          ),
        ],
      ],
    );
    if (action == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (action) {
      case BookMenuAction.removeFromReadList:
        await onRemoveFromReadList?.call();
      case BookMenuAction.addToReadList:
        await showReadListPickerSheet(
          context,
          bookIds: <String>[book.id],
          sourceKey: book.sourceKey,
        );
      case BookMenuAction.markPreviousRead:
        await onMarkPrevious?.call(read: true);
      case BookMenuAction.markPreviousUnread:
        await onMarkPrevious?.call(read: false);
      case BookMenuAction.editMetadata:
        await showEditLocalBookDialog(context, ref, book);
      case BookMenuAction.splitSeries:
        await ref
            .read(localCatalogMutatorProvider)
            .splitBookToOwnSeries(book.id, currentSeriesId: book.seriesId);
      case BookMenuAction.deleteFromDevice:
        final confirmed = await confirmDeleteLocalItems(context, count: 1);
        if (!confirmed) return;
        final seriesRemoved = await ref
            .read(localCatalogMutatorProvider)
            .deleteBook(book.id, seriesId: book.seriesId);
        if (seriesRemoved && context.mounted) {
          Navigator.of(context).maybePop();
        }
      case BookMenuAction.markRead:
      case BookMenuAction.markUnread:
        try {
          await ref
              .read(bookReadProvider.notifier)
              .setRead(
                book.id,
                read: action == BookMenuAction.markRead,
                pagesCount: book.pagesCount,
                seriesId: book.seriesId,
                sourceKey: book.sourceKey,
              );
          if (!context.mounted) return;
          // "读完自动删除"（DLD-01）：标记已读后按策略删掉这一本的下载。
          if (action == BookMenuAction.markRead) {
            await maybeDeleteReadDownload(ref, book);
          }
        } on ShelfFailure catch (failure) {
          messenger?.showSnackBar(
            SnackBar(content: Text(l10n.failureTitle(failure.kind))),
          );
        }
    }
  }
}

/// 书行长按菜单的动作。
enum BookMenuAction {
  removeFromReadList,
  addToReadList,
  markRead,
  markUnread,
  markPreviousRead,
  markPreviousUnread,
  editMetadata,
  splitSeries,
  deleteFromDevice,
}
