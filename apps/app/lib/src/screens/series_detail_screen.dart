import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/book_read_provider.dart';
import 'package:yomu/src/providers/book_selection_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/series_read_provider.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu/src/widgets/collection_picker_sheet.dart';
import 'package:yomu/src/widgets/edge_swipe_back.dart';
import 'package:yomu/src/widgets/offline_banner.dart';
import 'package:yomu/src/widgets/readlist_picker_sheet.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu/src/widgets/series_books_toolbar.dart';
import 'package:yomu/src/widgets/series_detail_app_bar.dart';
import 'package:yomu/src/widgets/series_hero_tag.dart';
import 'package:yomu/src/widgets/series_two_pane.dart';
import 'package:yomu/src/widgets/shelf_selection_bar.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情：头部（封面/进度）+ 书列表，点一本书进阅读器。
///
/// 窄屏是"头部 + 列表"一条滚动流；宽屏（`WindowSizeClass.expanded`）换成
/// 左头部 / 右书列表两栏，具体布局在 `widgets/series_two_pane.dart`。
class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({
    required this.seriesId,
    this.sourceKey,
    this.heroTag,
    super.key,
  });

  final String seriesId;

  /// 该系列所属内容源标识；为空时依次从祖先 [ScopedSourceScope] 或当前激活源回退。
  final String? sourceKey;

  /// 封面 Hero 的 tag：从货架进来时由 `SeriesDetailArgs` 带过来；
  /// 深链/冷启动没有源卡片时用默认 tag。
  final String? heroTag;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  String get seriesId => widget.seriesId;

  String? get _sourceKey =>
      widget.sourceKey ?? ScopedSourceScope.maybeOf(context);

  String? get _readSourceKey =>
      widget.sourceKey ?? ScopedSourceScope.readOf(context);

  String get heroTag => widget.heroTag ?? seriesHeroTag(seriesId);

  /// 排序与筛选（SER-01）：null = 服务端默认顺序 / 不筛选。
  BooksSort? _sort;
  SeriesReadStatus? _readStatus;

  @override
  void didUpdateWidget(SeriesDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seriesId != widget.seriesId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(bookSelectionProvider.notifier).exit();
      });
    }
  }

  SeriesQuery _seriesQuery(String? sourceKey) =>
      (sourceKey: sourceKey, seriesId: seriesId);

  SeriesBooksQuery _booksQuery(String? sourceKey) => (
    sourceKey: sourceKey,
    seriesId: seriesId,
    sort: _sort,
    readStatus: _readStatus,
  );

  Future<void> _refresh() async {
    final sourceKey = _readSourceKey;
    final seriesQuery = _seriesQuery(sourceKey);
    ref.invalidate(seriesDetailProvider(seriesQuery));
    ref.invalidate(seriesCollectionsProvider(seriesQuery));
    ref.invalidate(seriesBooksProvider);
    await ref.read(seriesBooksProvider(_booksQuery(sourceKey)).future);
  }

  /// 加载更多：调用增量分页器请求下一页 `page = 1, 2...`（ARC-12）。
  void _loadMore() => unawaited(
    ref
        .read(seriesBooksProvider(_booksQuery(_readSourceKey)).notifier)
        .loadMore(),
  );

  /// 进阅读器；回来时刷新进度。
  Future<void> _openBook(Book book, ReadingDirection direction) async {
    final sourceKey = _readSourceKey;
    final effectiveSource = sourceKey ?? book.sourceKey;
    await context.push(
      '/reader/${book.id}?source=${Uri.encodeComponent(effectiveSource)}',
      extra: ReaderArgs(
        book: book,
        direction: direction,
        sourceKey: effectiveSource,
      ),
    );
    ref.invalidate(seriesDetailProvider(_seriesQuery(sourceKey)));
    ref.invalidate(seriesBooksProvider);
  }

  bool _batchBusy = false;

  Future<void> _markSelectedBooks({required bool read}) async {
    final ids = ref.read(bookSelectionProvider).ids.toList();
    await _markBooks(ids, read: read);
    ref.read(bookSelectionProvider.notifier).exit();
  }

  Future<void> _addSelectedBooksToReadList() async {
    final ids = ref.read(bookSelectionProvider).ids.toList();
    if (ids.isEmpty || _batchBusy) return;
    final changed = await showReadListPickerSheet(
      context,
      bookIds: ids,
      sourceKey: _readSourceKey,
    );
    if (changed && mounted) {
      ref.read(bookSelectionProvider.notifier).exit();
    }
  }

  Future<void> _markManyBooks(List<String> bookIds, {required bool read}) =>
      _markBooks(bookIds, read: read);

  Future<void> _markBooks(List<String> bookIds, {required bool read}) async {
    if (bookIds.isEmpty || _batchBusy || !mounted) return;
    final sourceKey = _readSourceKey;
    setState(() => _batchBusy = true);
    final byId = <String, Book>{
      for (final book
          in ref
                  .read(seriesBooksProvider(_booksQuery(sourceKey)))
                  .value
                  ?.items ??
              const <Book>[])
        book.id: book,
    };
    final reader = ref.read(bookReadProvider.notifier);
    var failed = 0;
    for (final id in bookIds) {
      final book = byId[id];
      if (book == null) continue;
      try {
        await reader.setRead(
          id,
          read: read,
          pagesCount: book.pagesCount,
          seriesId: seriesId,
          sourceKey: sourceKey,
        );
      } on Object {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _batchBusy = false);
    ref.invalidate(seriesBooksProvider);
    ref.invalidate(seriesDetailProvider(_seriesQuery(sourceKey)));
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            failed == 0
                ? (read
                      ? l10n.batchMarkedRead(bookIds.length - failed)
                      : l10n.batchMarkedUnread(bookIds.length - failed))
                : l10n.batchPartialDone(bookIds.length - failed, failed),
          ),
        ),
      );
  }

  Future<void> _openCollectionsPicker() => showCollectionPickerSheet(
    context,
    seriesIds: <String>[seriesId],
    sourceKey: _readSourceKey,
  );

  Future<void> _markSeriesRead({required bool read}) async {
    try {
      await ref
          .read(seriesReadProvider.notifier)
          .setRead(seriesId, read: read, sourceKey: _readSourceKey);
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
    final sourceKey = _sourceKey;
    final seriesQuery = _seriesQuery(sourceKey);
    final detail = ref.watch(seriesDetailProvider(seriesQuery));
    final books = ref.watch(seriesBooksProvider(_booksQuery(sourceKey)));
    final inCollection =
        ref.watch(seriesCollectionsProvider(seriesQuery)).value?.isNotEmpty ??
        false;
    final series = detail.value;
    final page = books.value;
    final failure = books.error;
    final metadataLoading = !detail.hasValue && !detail.hasError;

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

    final wide =
        WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.expanded;
    final topPadding =
        MediaQuery.paddingOf(context).top + AppSizes.glassHeaderClearance;

    final content = PopScope(
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop && ref.read(bookSelectionProvider).active) {
          ref.read(bookSelectionProvider.notifier).exit();
        }
      },
      child: EdgeSwipeBack(
        child: Scaffold(
          extendBodyBehindAppBar: true,
          persistentFooterButtons: selection.active
              ? <Widget>[
                  ShelfBatchBar(
                    count: selection.ids.length,
                    busy: _batchBusy,
                    onMarkRead: () => _markSelectedBooks(read: true),
                    onMarkUnread: () => _markSelectedBooks(read: false),
                    extraLabel: l10n.batchAddToReadList,
                    extraIcon: Icons.playlist_add,
                    extraKey: const Key('books-batch-readlist'),
                    onExtraAction: _addSelectedBooksToReadList,
                  ),
                ]
              : null,
          appBar: buildSeriesDetailAppBar(
            context,
            ref,
            seriesId: seriesId,
            series: series,
            books: page?.items ?? const <Book>[],
            inCollection: inCollection,
            onOpenCollectionsPicker: _openCollectionsPicker,
            onMarkSeriesRead: _markSeriesRead,
          ),
          body: Stack(
            children: <Widget>[
              SeriesAdaptiveBody(
                wide: wide,
                series: series,
                books: page,
                failure: failure,
                metadataLoading: metadataLoading,
                seriesId: seriesId,
                heroTag: heroTag,
                topPadding: topPadding,
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
              OfflineOverlay(onRetry: () => unawaited(_refresh())),
            ],
          ),
        ),
      ),
    );
    return sourceKey == null
        ? content
        : ScopedSourceScope(sourceKey: sourceKey, child: content);
  }
}
