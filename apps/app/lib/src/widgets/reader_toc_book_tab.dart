import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 阅读器目录面板里的「本卷章节与书签」视图（LMB-05）。
class ReaderTocBookTab extends StatelessWidget {
  const ReaderTocBookTab({
    required this.chapters,
    required this.bookmarks,
    required this.currentPage,
    required this.palette,
    required this.onJumpPage,
    required this.onRemoveBookmark,
    super.key,
  });

  final List<BookChapter> chapters;
  final List<PageBookmark> bookmarks;
  final int currentPage;
  final ReaderPalette palette;
  final void Function(int page) onJumpPage;
  final void Function(int page) onRemoveBookmark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textStyle = AppTypography.of(context);

    final activeChapterIndex = _activeChapterIndex(chapters, currentPage);

    return ListView(
      key: const Key('reader-toc-book-list'),
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      children: <Widget>[
        if (bookmarks.isNotEmpty) ...<Widget>[
          _SectionHeading(
            key: const Key('reader-toc-bookmarks-section'),
            title: l10n.readerTocBookmarksHeading,
            palette: palette,
            textStyle: textStyle,
          ),
          for (final bm in bookmarks)
            ListTile(
              key: Key('reader-toc-bookmark-${bm.page}'),
              onTap: () => onJumpPage(bm.page),
              leading: Icon(
                Icons.bookmark,
                color: bm.page == currentPage
                    ? palette.foreground
                    : palette.muted,
              ),
              title: Text(
                bm.note.isNotEmpty
                    ? bm.note
                    : l10n.readerTocPageNumber(bm.page),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle.body.copyWith(
                  color: palette.foreground,
                  fontWeight: bm.page == currentPage
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              subtitle: bm.note.isNotEmpty
                  ? Text(
                      l10n.readerTocPageNumber(bm.page),
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: palette.muted),
                    )
                  : null,
              trailing: IconButton(
                key: Key('reader-toc-bookmark-delete-${bm.page}'),
                tooltip: l10n.readerBookmarkDelete,
                icon: Icon(
                  Icons.delete_outline,
                  color: palette.muted,
                  size: AppSizes.iconMd,
                ),
                onPressed: () => onRemoveBookmark(bm.page),
              ),
            ),
        ],
        if (chapters.isNotEmpty) ...<Widget>[
          _SectionHeading(
            key: const Key('reader-toc-chapters-section'),
            title: l10n.readerTocChaptersHeading,
            palette: palette,
            textStyle: textStyle,
          ),
          for (var i = 0; i < chapters.length; i++)
            ListTile(
              key: Key('reader-toc-chapter-$i'),
              onTap: () => onJumpPage(chapters[i].startPage),
              leading: Icon(
                i == activeChapterIndex
                    ? Icons.play_arrow
                    : Icons.article_outlined,
                color: i == activeChapterIndex
                    ? palette.foreground
                    : palette.muted,
              ),
              title: Text(
                chapters[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle.body.copyWith(
                  color: palette.foreground,
                  fontWeight: i == activeChapterIndex
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
              trailing: Text(
                l10n.readerTocPageNumber(chapters[i].startPage),
                style: textStyle.progressNumber.copyWith(color: palette.muted),
              ),
            ),
        ],
      ],
    );
  }

  static int _activeChapterIndex(List<BookChapter> chapters, int currentPage) {
    var active = -1;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].startPage <= currentPage) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.palette,
    required this.textStyle,
    super.key,
  });

  final String title;
  final ReaderPalette palette;
  final AppTypography textStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: textStyle.caption.copyWith(
          color: palette.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 目录面板「系列各卷」分段中的单本分卷行。
class ReaderTocVolumeRow extends StatelessWidget {
  const ReaderTocVolumeRow({
    required this.book,
    required this.palette,
    required this.textStyle,
    required this.isCurrent,
    this.onTap,
    super.key,
  });

  final Book book;
  final ReaderPalette palette;
  final AppTypography textStyle;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progress = book.readProgress;
    final subtitle = progress == null
        ? l10n.bookPages(book.pagesCount)
        : book.isCompleted
        ? l10n.bookReadPages(book.pagesCount)
        : l10n.bookPageProgress(progress.page, book.pagesCount);

    return ListTile(
      key: Key('reader-toc-book-${book.id}'),
      onTap: onTap,
      enabled: !isCurrent,
      leading: Icon(
        isCurrent ? Icons.play_arrow : Icons.menu_book_outlined,
        color: isCurrent ? palette.foreground : palette.muted,
      ),
      title: Text(
        book.number.isEmpty ? book.name : '#${book.number} · ${book.name}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle.body.copyWith(
          color: palette.foreground,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        isCurrent ? l10n.readerTocCurrent(subtitle) : subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: palette.muted),
      ),
      trailing: isCurrent
          ? Icon(Icons.check, color: palette.foreground, size: AppSizes.iconMd)
          : null,
    );
  }
}
