import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/reader_toc_providers.dart';
import 'package:yomu/src/screens/reader_args.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_toc_book_tab.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

enum _TocSegment { book, volumes }

/// 阅读器里的"目录"（RDR-02 + LMB-05）：
/// - 当本卷有内部章节（EPUB TOC / 多子目录 / ComicInfo 书签）或页级书签时，
///   展示「本卷章节与书签」+「系列各卷」分段视图；
/// - 否则自动隐藏分段栏，直接展示系列各卷（保持简洁）。
Future<void> showReaderTocSheet(
  BuildContext context, {
  String? seriesId,
  required String currentBookId,
  required ReaderPalette palette,
  required ReadingDirection direction,
  int currentPage = 1,
  void Function(int page)? onJump,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (BuildContext context) => FrostedSurface(
      kind: AppMaterialKind.sheet,
      material: AppMaterial.resolve(
        AppMaterialKind.sheet,
        eink: palette.isEink,
        dark: !palette.isEink,
      ),
      shape: AppShapes.sheet(eink: palette.isEink),
      child: Material(
        type: MaterialType.transparency,
        child: ReaderTocSheet(
          seriesId: seriesId,
          currentBookId: currentBookId,
          palette: palette,
          direction: direction,
          currentPage: currentPage,
          onJump: onJump,
        ),
      ),
    ),
  );
}

class ReaderTocSheet extends ConsumerStatefulWidget {
  const ReaderTocSheet({
    this.seriesId,
    required this.currentBookId,
    required this.palette,
    required this.direction,
    this.currentPage = 1,
    this.onJump,
    super.key,
  });

  final String? seriesId;
  final String currentBookId;
  final ReaderPalette palette;

  /// 换书时沿用同一个方向（否则 RTL 系列换一本就反着翻）。
  final ReadingDirection direction;

  /// 当前 1 基页码（用于高亮所处章节与书签）。
  final int currentPage;

  /// 选中书内章节或书签后的跳页回调。
  final void Function(int page)? onJump;

  @override
  ConsumerState<ReaderTocSheet> createState() => _ReaderTocSheetState();
}

class _ReaderTocSheetState extends ConsumerState<ReaderTocSheet> {
  static const double _rowHeight = 72;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _currentKey = GlobalKey();
  bool _scrolledToCurrent = false;
  _TocSegment? _userSegment;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _ensureCurrentVisible() {
    if (_scrolledToCurrent) return;
    final context = _currentKey.currentContext;
    if (context == null) return;
    _scrolledToCurrent = true;
    Scrollable.ensureVisible(
      context,
      alignment: 0.32,
      duration: AppMotion.of(this.context).emphasized,
    );
  }

  void _openBook(Book book) {
    final route = '/reader/${book.id}';
    Navigator.of(context).pop();
    this.context.pushReplacement(
      route,
      extra: ReaderArgs(book: book, direction: widget.direction),
    );
  }

  void _jumpToPage(int page) {
    Navigator.of(context).pop();
    widget.onJump?.call(page);
  }

  void _removeBookmark(int page) {
    unawaited(
      ref
          .read(bookmarkControllerProvider)
          .remove(bookId: widget.currentBookId, page: page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = widget.palette;
    final textStyle = AppTypography.of(context);

    final chapters =
        ref.watch(bookChaptersProvider(widget.currentBookId)).value ??
        const <BookChapter>[];
    final bookmarks =
        ref.watch(bookBookmarksProvider(widget.currentBookId)).value ??
        const <PageBookmark>[];
    final hasBookEntries = chapters.isNotEmpty || bookmarks.isNotEmpty;
    final hasSeries = widget.seriesId != null;

    final effectiveSegment = !hasBookEntries
        ? _TocSegment.volumes
        : !hasSeries
        ? _TocSegment.book
        : (_userSegment ?? _TocSegment.book);

    final Widget body;
    if (effectiveSegment == _TocSegment.book && hasBookEntries) {
      body = ReaderTocBookTab(
        chapters: chapters,
        bookmarks: bookmarks,
        currentPage: widget.currentPage,
        palette: palette,
        onJumpPage: _jumpToPage,
        onRemoveBookmark: _removeBookmark,
      );
    } else if (hasSeries) {
      final query = (seriesId: widget.seriesId!, sort: null, readStatus: null);
      final async = ref.watch(seriesBooksProvider(query));
      body = _buildVolumesBody(context, l10n, palette, textStyle, async);
    } else {
      body = Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          l10n.noBooksYet,
          style: textStyle.body.copyWith(color: palette.muted),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    l10n.readerToc,
                    style: textStyle.headline.copyWith(
                      color: palette.foreground,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('reader-toc-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: palette.muted,
                    tooltip: l10n.close,
                  ),
                ],
              ),
            ),
            if (hasBookEntries && hasSeries)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: GlassSegmentedControl<_TocSegment>(
                  key: const Key('reader-toc-segment'),
                  selected: effectiveSegment,
                  onSelected: (_TocSegment next) =>
                      setState(() => _userSegment = next),
                  segments: <GlassSegment<_TocSegment>>[
                    GlassSegment<_TocSegment>(
                      key: const Key('reader-toc-tab-book'),
                      value: _TocSegment.book,
                      label: l10n.readerTocTabBook,
                    ),
                    GlassSegment<_TocSegment>(
                      key: const Key('reader-toc-tab-volumes'),
                      value: _TocSegment.volumes,
                      label: l10n.readerTocTabVolumes,
                    ),
                  ],
                ),
              ),
            Flexible(child: body),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumesBody(
    BuildContext context,
    AppLocalizations l10n,
    ReaderPalette palette,
    AppTypography textStyle,
    AsyncValue<PageResult<Book>> async,
  ) {
    if (async.hasError && !async.hasValue) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          async.error is ShelfFailure
              ? l10n.failureTitle((async.error! as ShelfFailure).kind)
              : l10n.errorGeneric,
          style: textStyle.body.copyWith(color: palette.muted),
        ),
      );
    }
    final page = async.value;
    if (page == null) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (page.items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          l10n.noBooksYet,
          style: textStyle.body.copyWith(color: palette.muted),
        ),
      );
    }

    final currentIndex = page.items.indexWhere(
      (Book book) => book.id == widget.currentBookId,
    );
    if (!_scroll.hasClients && currentIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final offset = (currentIndex * _rowHeight).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        );
        _scroll.jumpTo(offset);
      });
    }

    return ListView.builder(
      key: const Key('reader-toc-list'),
      controller: _scroll,
      itemCount: page.items.length,
      itemExtent: _rowHeight,
      itemBuilder: (BuildContext context, int index) {
        final book = page.items[index];
        final isCurrent = book.id == widget.currentBookId;
        final key = isCurrent ? _currentKey : null;
        if (isCurrent) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _ensureCurrentVisible(),
          );
        }
        return ReaderTocVolumeRow(
          key: key,
          book: book,
          palette: palette,
          textStyle: textStyle,
          isCurrent: isCurrent,
          onTap: isCurrent ? null : () => _openBook(book),
        );
      },
    );
  }
}
