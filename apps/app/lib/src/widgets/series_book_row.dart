import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/book_read_provider.dart';
import 'package:komga_native/src/providers/download_policy_gate.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/book_download_button.dart';
import 'package:komga_native/src/widgets/context_menu.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
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

  /// 搜索结果里书是**脱离系列**出现的：标题前要补系列名，
  /// 否则一屏都是 "Vol. 1 / Vol. 2"，分不清是哪套书（FIX-06）。
  final bool showSeriesTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = ref.watch(bookCoverProvider(book.id));
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
              BookDownloadButton(book: book),
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

  /// 长按一本书：标记这一本已读/未读；在系列页还可以"标记之前所有"。
  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    unawaited(AppHaptics.light());
    // 用枚举而不是 bool：单本和"之前所有"是两组不同的动作，
    // 以前两组共用一个 true/false，点"之前所有"会被当成"标记这一本"（踩过）。
    final action = await showContextMenu<BookMenuAction>(
      context: context,
      anchor: context,
      entries: <ContextMenuEntry<BookMenuAction>>[
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
      ],
    );
    if (action == null) return;
    switch (action) {
      case BookMenuAction.markPreviousRead:
        await onMarkPrevious?.call(read: true);
      case BookMenuAction.markPreviousUnread:
        await onMarkPrevious?.call(read: false);
      case BookMenuAction.markRead:
      case BookMenuAction.markUnread:
        await ref
            .read(bookReadProvider.notifier)
            .setRead(
              book.id,
              read: action == BookMenuAction.markRead,
              pagesCount: book.pagesCount,
            );
        if (!context.mounted) return;
        // 书列表是"本地进度叠加"出来的，改完要让详情重新取一遍。
        ref.invalidate(seriesBooksProvider);
        ref.invalidate(seriesDetailProvider(book.seriesId));
        // "读完自动删除"（DLD-01）：标记已读后按策略删掉这一本的下载。
        if (action == BookMenuAction.markRead) {
          await maybeDeleteReadDownload(ref, book);
        }
    }
  }
}

/// 书行长按菜单的动作。
enum BookMenuAction {
  markRead,
  markUnread,
  markPreviousRead,
  markPreviousUnread,
}
