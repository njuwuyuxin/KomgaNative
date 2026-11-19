import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/book_read_provider.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/book_download_button.dart';
import 'package:komga_native/src/widgets/context_menu.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 一本书：封图 + 标题 + 页数/已读状态，点进去读。
///
/// 整行是一个按钮；读屏只播报「标题 + 页数/已读」，下载按钮仍是独立控件。
class SeriesBookRow extends ConsumerWidget {
  const SeriesBookRow({required this.book, required this.onOpen, super.key});

  final Book book;
  final Future<void> Function() onOpen;

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
    final title = book.number.isEmpty
        ? book.name
        : '#${book.number} · ${book.name}';
    final status = completed
        ? l10n.bookReadPages(book.pagesCount)
        : l10n.bookPages(book.pagesCount);

    return Semantics(
      key: Key('book-${book.id}'),
      container: true,
      button: true,
      label: '$title, $status',
      onTap: () => unawaited(onOpen()),
      child: PressableScale(
        child: ListTile(
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
          onTap: () => unawaited(onOpen()),
          onLongPress: () => unawaited(_showMenu(context, ref)),
        ),
      ),
    );
  }

  /// 长按一本书：标记已读 / 未读（UI-P2-5 顺带补上的单本书标记）。
  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    unawaited(AppHaptics.light());
    final action = await showContextMenu<bool>(
      context: context,
      anchor: context,
      entries: <ContextMenuEntry<bool>>[
        ContextMenuEntry(
          value: true,
          label: l10n.bookMarkRead,
          icon: Icons.done,
        ),
        ContextMenuEntry(
          value: false,
          label: l10n.bookMarkUnread,
          icon: Icons.remove_done,
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    await ref
        .read(bookReadProvider.notifier)
        .setRead(book.id, read: action, pagesCount: book.pagesCount);
    if (!context.mounted) return;
    // 书列表是"本地进度叠加"出来的，改完要让详情重新取一遍。
    ref.invalidate(seriesBooksProvider);
    ref.invalidate(seriesDetailProvider(book.seriesId));
  }
}
