import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/l10n/failure_text.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/book_read_provider.dart';
import 'package:komga_native/src/providers/book_selection_provider.dart';
import 'package:komga_native/src/providers/collections_controller.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/series_read_provider.dart';
import 'package:komga_native/src/widgets/shelf_selection_bar.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/widgets/edge_swipe_back.dart';
import 'package:komga_native/src/widgets/offline_banner.dart';
import 'package:komga_native/src/widgets/series_download_menu.dart';
import 'package:komga_native/src/widgets/series_hero_tag.dart';
import 'package:komga_native/src/widgets/series_books_toolbar.dart';
import 'package:komga_native/src/widgets/series_two_pane.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情：头部（封面/进度）+ 书列表，点一本书进阅读器。
///
/// 窄屏是"头部 + 列表"一条滚动流；宽屏（`WindowSizeClass.expanded`）换成
/// 左头部 / 右书列表两栏，具体布局在 `widgets/series_two_pane.dart`。
///
/// **头部第一帧就渲染**，不等任何请求：从书架点进来时，封面 Hero 的终点必须
/// 在首帧存在，共享元素动画才会播；元信息（标题/作者/进度/主按钮）与书列表
/// 各自异步到，未到时用骨架占位。这样首次打开和第二次打开是同一段动画，
/// 不会出现"第一次全屏加载、第二次才飞"。
///
/// 为什么是 StatefulWidget：书列表要能"加载更多"（UI-P2-4 解除 100 本上限），
/// 而"要多少本"是**视图状态**（重进详情页从 100 本重新开始就够），
/// 所以放在页面里，请求本身仍然只发生在 Repository 层。
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({required this.seriesId, this.heroTag, super.key});

  final String seriesId;

  /// 封面 Hero 的 tag：从货架进来时由 `SeriesDetailArgs` 带过来（同一页面上
  /// 同一个系列可能有多份副本）；深链/冷启动没有源卡片时用默认 tag。
  final String? heroTag;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  String get seriesId => widget.seriesId;

  /// 封面 Hero tag：源卡片带来的优先，否则按默认 `series-<id>`。
  String get heroTag => widget.heroTag ?? seriesHeroTag(seriesId);

  /// 排序与筛选（SER-01）：null = 服务端默认顺序 / 不筛选。
  BooksSort? _sort;
  SeriesReadStatus? _readStatus;

  SeriesBooksQuery get _booksQuery =>
      (seriesId: seriesId, sort: _sort, readStatus: _readStatus);

  Future<void> _refresh() async {
    ref.invalidate(seriesDetailProvider(seriesId));
    ref.invalidate(seriesBooksProvider);
    await ref.read(seriesBooksProvider(_booksQuery).future);
  }

  /// 加载更多：调用增量分页器请求下一页 `page = 1, 2...`（ARC-12）。
  void _loadMore() =>
      unawaited(ref.read(seriesBooksProvider(_booksQuery).notifier).loadMore());

  /// 进阅读器；回来时刷新进度。不刷新的话"读完还是 0 of N"（真机上撞到过）。
  Future<void> _openBook(Book book, ReadingDirection direction) async {
    await context.push(
      '/reader/${book.id}',
      extra: ReaderArgs(book: book, direction: direction),
    );
    ref.invalidate(seriesDetailProvider(seriesId));
    ref.invalidate(seriesBooksProvider);
  }

  /// 批量条正在提交（避免连点）。
  bool _batchBusy = false;

  /// 对选中的书批量标记（SER-02）：逐个调用，失败不中断，最后统一提示。
  Future<void> _markSelectedBooks({required bool read}) async {
    final ids = ref.read(bookSelectionProvider).ids.toList();
    await _markBooks(ids, read: read);
    ref.read(bookSelectionProvider.notifier).exit();
  }

  /// 长按菜单里的"标记之前所有为已读/未读"。
  Future<void> _markManyBooks(List<String> bookIds, {required bool read}) =>
      _markBooks(bookIds, read: read);

  Future<void> _markBooks(List<String> bookIds, {required bool read}) async {
    if (bookIds.isEmpty || _batchBusy || !mounted) return;
    setState(() => _batchBusy = true);
    final byId = <String, Book>{
      for (final book
          in ref.read(seriesBooksProvider(_booksQuery)).value?.items ??
              const <Book>[])
        book.id: book,
    };
    final reader = ref.read(bookReadProvider.notifier);
    var failed = 0;
    for (final id in bookIds) {
      final book = byId[id];
      if (book == null) continue;
      try {
        await reader.setRead(id, read: read, pagesCount: book.pagesCount);
      } on Object {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _batchBusy = false);
    // 原地刷新：书列表是"本地进度叠加"出来的，不刷新会留着旧状态。
    ref.invalidate(seriesBooksProvider);
    ref.invalidate(seriesDetailProvider(seriesId));
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? l10n.booksBatchDone(bookIds.length - failed)
              : l10n.batchPartialDone(bookIds.length - failed, failed),
        ),
      ),
    );
  }

  /// 新建收藏集并以本系列为第一个成员（SER-04）。
  ///
  /// 为什么不是"新建空收藏集"：Komga 实测 `seriesIds` 至少一个，空集直接 400。
  Future<void> _createCollection() async {
    final l10n = AppLocalizations.of(context);
    var draft = '';
    final name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('collection-create-dialog'),
        title: Text(l10n.collectionCreate),
        content: TextFormField(
          key: const Key('collection-create-field'),
          initialValue: draft,
          autofocus: true,
          onChanged: (String value) => draft = value,
          decoration: InputDecoration(hintText: l10n.collectionNameHint),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('collection-create-ok'),
            onPressed: () => Navigator.of(context).pop(draft.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .create(name: name, seriesIds: <String>[seriesId]);
      messenger.showSnackBar(SnackBar(content: Text(l10n.collectionSaved)));
    } on ShelfFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  /// 标记整系列已读/未读；失败时用 SnackBar 说明，不把详情页变成错误页。
  Future<void> _markSeriesRead({required bool read}) async {
    try {
      await ref.read(seriesReadProvider.notifier).setRead(seriesId, read: read);
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).failureTitle(failure.kind),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(seriesDetailProvider(seriesId));
    final books = ref.watch(seriesBooksProvider(_booksQuery));
    final series = detail.value;
    final page = books.value;
    final failure = books.error;

    // 注意：Riverpod 3 里"首次加载失败"会表现为 AsyncLoading + hasError，
    // 用 `AsyncError` 模式匹配会掉进 loading 分支（踩过）。这里按 hasError/value 判断。
    // hasError 也算"元信息已就绪"：请求失败时头部退回兜底标题，不能永远停在骨架上。
    final metadataLoading = !detail.hasValue && !detail.hasError;

    // 排序 / 筛选（SER-01）：放在书列表上方，窄屏宽屏共用同一个工具条。
    final filtered = _sort != null || _readStatus != null;
    final selection = ref.watch(bookSelectionProvider);
    final selecting = ref.read(bookSelectionProvider.notifier);
    final bookIds = <String>[
      for (final book in page?.items ?? <Book>[]) book.id,
    ];
    final toolbar = SeriesBooksToolbar(
      total: page?.totalElements ?? 0,
      sort: _sort,
      readStatus: _readStatus,
      onSort: (BooksSort? value) => setState(() => _sort = value),
      onReadStatus: (SeriesReadStatus? value) =>
          setState(() => _readStatus = value),
      selecting: selection.active,
      selectedCount: selection.ids.length,
      allSelected: bookIds.isNotEmpty && selection.ids.length == bookIds.length,
      onEnterSelection: selecting.enter,
      onExitSelection: selecting.exit,
      onSelectAll: () => selecting.selectAll(bookIds),
    );

    // 宽屏两栏；窄屏一条滚动流。断点判断只在这里做一次（WindowSizeClass）。
    final wide =
        WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.expanded;

    return EdgeSwipeBack(
      child: Scaffold(
        // 多选批量条：与书架一致，放在 footer 而不是浮层，避免盖住最后一行。
        persistentFooterButtons: selection.active
            ? <Widget>[
                ShelfBatchBar(
                  count: selection.ids.length,
                  busy: _batchBusy,
                  onMarkRead: () => _markSelectedBooks(read: true),
                  onMarkUnread: () => _markSelectedBooks(read: false),
                ),
              ]
            : null,
        appBar: GlassTopBar(
          header: GlassHeader(
            leading: GlassIconButton(
              icon: Icons.chevron_left,
              label: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => context.pop(),
            ),
            // 刻意不放标题：系列名在头部（封面右边）已经有了，标题栏再重复一次
            // 既挤占宽度又显得多余。这里只留返回 / 下载 / 更多。
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SeriesDownloadMenu(
                  seriesId: seriesId,
                  books: page?.items ?? const <Book>[],
                ),
                GlassMenuButton(
                  key: const Key('series-mark-menu'),
                  orb: true,
                  icon: Icons.done_all,
                  label: l10n.markReadTooltip,
                  menuChildren: <Widget>[
                    GlassMenuItemButton(
                      key: const Key('series-mark-read'),
                      label: l10n.markAllRead,
                      onPressed: () => unawaited(_markSeriesRead(read: true)),
                    ),
                    GlassMenuItemButton(
                      key: const Key('series-mark-unread'),
                      label: l10n.markAllUnread,
                      onPressed: () => unawaited(_markSeriesRead(read: false)),
                    ),
                    // Komga 实测要求新建收藏集至少带一个系列（空集 400），
                    // 所以入口放在系列页：以本系列为第一个成员。
                    GlassMenuItemButton(
                      key: const Key('series-create-collection'),
                      label: l10n.collectionCreate,
                      onPressed: () => unawaited(_createCollection()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: Column(
          children: <Widget>[
            OfflineBanner(onRetry: () => unawaited(_refresh())),
            Expanded(
              child: wide
                  ? SeriesTwoPane(
                      series: series,
                      books: page,
                      failure: failure,
                      metadataLoading: metadataLoading,
                      seriesId: seriesId,
                      heroTag: heroTag,
                      onRefresh: _refresh,
                      onRetry: () => unawaited(_refresh()),
                      onLoadMore: _loadMore,
                      onOpenBook: _openBook,
                      toolbar: toolbar,
                      filtered: filtered,
                      selected: selection.ids,
                      selecting: selection.active,
                      onToggleSelect: selecting.toggle,
                      onMarkManyBooks: _markManyBooks,
                    )
                  : SeriesSinglePane(
                      series: series,
                      books: page,
                      failure: failure,
                      metadataLoading: metadataLoading,
                      seriesId: seriesId,
                      heroTag: heroTag,
                      onRefresh: _refresh,
                      onRetry: () => unawaited(_refresh()),
                      onLoadMore: _loadMore,
                      onOpenBook: _openBook,
                      toolbar: toolbar,
                      filtered: filtered,
                      selected: selection.ids,
                      selecting: selection.active,
                      onToggleSelect: selecting.toggle,
                      onMarkManyBooks: _markManyBooks,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
