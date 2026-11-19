import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_args.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读器里的"目录"（RDR-02）：本系列的书列表，点一本直接换书。
///
/// 为什么不是"章节树"：Komga 的书就是文件（`Vol. 1` / `卷01`），没有比书更细的
/// 结构化章节；Panels/Aidoku 的目录在这个数据模型下也是"这一系列的书"。
///
/// 三个细节：
/// - 打开时**滚到当前这本**：20+ 本的系列不定位的话，用户每次都要自己找；
/// - 换书用 `pushReplacement`：连读十本不该压十层返回栈，返回仍然是系列页；
/// - 高亮当前这本并显示读过的页数，避免"点到刚才那本"。
Future<void> showReaderTocSheet(
  BuildContext context, {
  required String seriesId,
  required String currentBookId,
  required ReaderPalette palette,
  required ReadingDirection direction,
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
        ),
      ),
    ),
  );
}

class ReaderTocSheet extends ConsumerStatefulWidget {
  const ReaderTocSheet({
    required this.seriesId,
    required this.currentBookId,
    required this.palette,
    required this.direction,
    super.key,
  });

  final String seriesId;
  final String currentBookId;
  final ReaderPalette palette;

  /// 换书时沿用同一个方向（否则 RTL 系列换一本就反着翻）。
  final ReadingDirection direction;

  @override
  ConsumerState<ReaderTocSheet> createState() => _ReaderTocSheetState();
}

class _ReaderTocSheetState extends ConsumerState<ReaderTocSheet> {
  /// 一行的高度：只用来给"打开时定位到当前书"一个初始偏移。
  static const double _rowHeight = 72;

  /// 一次要多少本。目录是本地列表，多取一些没有额外代价（一份 JSON）。
  static const int _size = 300;

  final ScrollController _scroll = ScrollController();
  final GlobalKey _currentKey = GlobalKey();
  bool _scrolledToCurrent = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 首帧之后把当前书精确滚进视野。
  ///
  /// 初始偏移只是"大概位置"（按固定行高估），定位到真正的行还要
  /// `ensureVisible`：书名可能占两行、缩略图可能更高。
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

  void _open(Book book) {
    final route = '/reader/${book.id}';
    Navigator.of(context).pop();
    // 替换当前阅读器页：连读十本不会压十层返回栈。
    this.context.pushReplacement(
      route,
      extra: ReaderArgs(book: book, direction: widget.direction),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = widget.palette;
    final textStyle = AppTypography.of(context);
    final query = (seriesId: widget.seriesId, size: _size);
    final async = ref.watch(seriesBooksProvider(query));

    final body = _buildBody(context, l10n, palette, textStyle, async);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // 面板最多占 3/4 屏：再高就没有"弹出来"的感觉了。
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
            Flexible(child: body),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
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
              ? (async.error! as ShelfFailure).message
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
    if (_scroll.hasClients == false && currentIndex > 0) {
      // 还没挂上 controller 时给一个初始偏移，避免"打开就停在第一本"。
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
        // 当前行挂 key：首帧后 ensureVisible 用它精确定位。
        final key = isCurrent ? _currentKey : null;
        if (isCurrent) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _ensureCurrentVisible(),
          );
        }
        return _TocRow(
          key: key,
          book: book,
          palette: palette,
          textStyle: textStyle,
          isCurrent: isCurrent,
          onTap: isCurrent ? null : () => _open(book),
        );
      },
    );
  }
}

class _TocRow extends StatelessWidget {
  const _TocRow({
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
    // 进度里已经含总页数（`第 114/227 页`），不要再拼一遍 `227 页`。
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
          color: isCurrent ? palette.foreground : palette.foreground,
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
