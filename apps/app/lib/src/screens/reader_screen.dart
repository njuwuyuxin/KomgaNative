import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_native/src/widgets/reader_vertical_view.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

/// 打开阅读器时从列表页带过来的上下文。
///
/// 阅读方向存在 `Series.metadata` 里、不在 `Book` 上，所以必须显式带过来；
/// 深链没有它时按从左到右处理（默认值）。
class ReaderArgs {
  const ReaderArgs({
    required this.book,
    this.direction = ReadingDirection.unknown,
  });

  final Book book;
  final ReadingDirection direction;
}

/// 漫画阅读器：单页 / 双页跨页 / 纵向连续。
///
/// 分工：
/// - 本类只做**编排**——当前页、阅读模式、进度回写、生命周期；
/// - 绘制在 `ReaderPagedView` / `ReaderVerticalView`；
/// - 几何在 `komga_reader_engine`（纯函数，单测覆盖）。
///
/// 模式默认值跟随系列元数据：条漫/竖向作品直接进纵向连续，其余先单页；
/// 用户随时可以在顶栏切换，切完页码不丢。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    required this.bookId,
    this.book,
    this.direction = ReadingDirection.unknown,
    super.key,
  });

  final String bookId;

  /// 从系列详情带过来的书；深链时为空，用 [readerBookProvider] 现取。
  final Book? book;

  final ReadingDirection direction;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  /// 翻页后多久回写进度：连续翻页时只写最后停下的那一页。
  static const Duration _saveDelay = Duration(milliseconds: 600);

  /// 预取前后几页，翻页时不用等网络（纵向模式由 ListView 自己预取）。
  static const List<int> _prefetchOffsets = <int>[1, -1, 2];

  /// 1 基当前页；0 表示"还没翻过页"，此时用服务端进度恢复位置。
  int _page = 0;
  int _lastSaved = 0;
  bool _chromeVisible = true;
  Timer? _saveTimer;

  /// null = 还没手动选过，跟随系列方向。
  ReadingMode? _mode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    super.dispose();
  }

  /// 切后台/锁屏时立刻落一次进度：只靠防抖会丢掉"看完就退出"的那一页。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _saveTimer?.cancel();
    final total =
        ref.read(readerPagesProvider(widget.bookId)).value?.length ?? 0;
    if (total == 0) return;
    unawaited(_persist(_resolvePage(total), total));
  }

  ReadingMode _defaultMode(ReadingDirection direction) =>
      direction.isScroll ? ReadingMode.verticalScroll : ReadingMode.paged;

  /// 条漫/竖向作品默认纵向连续；双页是用户主动选的（元数据表达不了）。
  ReadingMode _modeFor(ReadingDirection direction) =>
      _mode ?? _defaultMode(direction);

  int _resolvePage(int total) {
    if (total <= 0) return 1;
    if (_page > 0) return _page.clamp(1, total);
    final resumed =
        (widget.book ?? ref.read(readerBookProvider(widget.bookId)).value)
            ?.readProgress
            ?.page ??
        1;
    return resumed.clamp(1, total);
  }

  Future<void> _persist(int page, int total) async {
    if (page == _lastSaved) return;
    try {
      await ref
          .read(readerRepositoryProvider)
          .saveProgress(
            widget.bookId,
            page: page,
            completed: _isCompleted(page: page, total: total),
          );
      _lastSaved = page;
    } on ShelfFailure {
      // 进度回写失败不打断阅读：下次翻页会再试，切后台时也会再 flush 一次。
    }
  }

  /// 是否已经读到结尾。
  ///
  /// 双页模式下"最后一屏"可能包含倒数两页，此时 `page` 到不了 `total`，
  /// 只看页码会漏掉 `completed`，进度条永远差一页。
  bool _isCompleted({required int page, required int total}) {
    if (page >= total) return true;
    if (_modeFor(widget.direction) != ReadingMode.doublePage) return false;
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
    if (pages == null || pages.isEmpty) return false;
    final spreads = _spreadsFor(pages, ReadingMode.doublePage);
    final index = spreadIndexOf(spreads, page - 1);
    return index >= 0 && spreads[index].contains(pages.length - 1);
  }

  void _scheduleSave(int page, int total) {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, () {
      unawaited(_persist(page, total));
    });
  }

  Future<void> _warm(int page) async {
    try {
      await ref.read(
        readerPageImageProvider((bookId: widget.bookId, page: page)).future,
      );
    } on ShelfFailure {
      // 预取失败无所谓：真的翻到那一页时会重新请求并显示错误/重试。
    }
  }

  void _prefetch(int current, int total) {
    for (final offset in _prefetchOffsets) {
      final target = current + offset;
      if (target < 1 || target > total) continue;
      unawaited(_warm(target));
    }
  }

  void _setPage(int page, int total, {bool prefetch = true}) {
    if (page == _page) return;
    setState(() => _page = page);
    if (prefetch) _prefetch(page, total);
    _scheduleSave(page, total);
  }

  /// 双页模式下翻页的粒度是"一跨页"，单页是"一页"。
  void _turn(
    int delta,
    int total,
    ReadingMode mode,
    int spreadIndex,
    List<List<int>> spreads,
  ) {
    if (mode == ReadingMode.verticalScroll) return;
    if (mode == ReadingMode.doublePage && spreads.isNotEmpty) {
      final next = (spreadIndex + delta).clamp(0, spreads.length - 1);
      if (next == spreadIndex) return;
      _setPage(spreads[next].first + 1, total);
      return;
    }
    final current = _resolvePage(total);
    _setPage((current + delta).clamp(1, total), total);
  }

  List<List<int>> _spreadsFor(List<PageInfo> pages, ReadingMode mode) {
    if (mode != ReadingMode.doublePage) {
      return const <List<int>>[];
    }
    return buildSpreads(
      pageCount: pages.length,
      aspectAt: (int index) {
        final info = pages[index];
        return PageAspect(
          width: info.width?.toDouble(),
          height: info.height?.toDouble(),
        );
      },
    );
  }

  String _pageLabel(ReadingMode mode, int page, int total, List<int> spread) {
    if (mode == ReadingMode.doublePage && spread.length > 1) {
      return '${spread.first + 1}–${spread.last + 1} / $total';
    }
    return '$page / $total';
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(
      isEink: ref.watch(settingsProvider).forceEink,
    );
    final bookAsync = ref.watch(readerBookProvider(widget.bookId));
    final book = widget.book ?? bookAsync.value;
    final pagesAsync = ref.watch(readerPagesProvider(widget.bookId));
    final pagesError = pagesAsync.error;
    final pages = pagesAsync.value;

    if (pagesError != null) {
      return ReaderFailure(
        failure: pagesError,
        palette: palette,
        onRetry: () => ref.invalidate(readerPagesProvider(widget.bookId)),
      );
    }
    if (pages == null) {
      return Scaffold(
        backgroundColor: palette.background,
        body: Center(child: CircularProgressIndicator(color: palette.muted)),
      );
    }
    if (pages.isEmpty) {
      return ReaderFailure(
        failure: const ProtocolFailure(),
        palette: palette,
        title: 'This book has no pages',
        onRetry: () => ref.invalidate(readerPagesProvider(widget.bookId)),
      );
    }

    final total = pages.length;
    final mode = _modeFor(widget.direction);
    final page = _resolvePage(total);
    final spreads = _spreadsFor(pages, mode);
    final spreadIndex = spreads.isEmpty ? -1 : spreadIndexOf(spreads, page - 1);
    final spread = spreads.isEmpty
        ? <int>[page - 1]
        : spreads[spreadIndex < 0 ? 0 : spreadIndex];
    final rightToLeft = widget.direction.isRightToLeft;
    final canGoBack = switch (mode) {
      ReadingMode.paged => page > 1,
      ReadingMode.doublePage => spreadIndex > 0,
      ReadingMode.verticalScroll => false,
    };
    final canGoForward = switch (mode) {
      ReadingMode.paged => page < total,
      ReadingMode.doublePage =>
        spreadIndex >= 0 && spreadIndex < spreads.length - 1,
      ReadingMode.verticalScroll => false,
    };

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            if (_chromeVisible)
              ReaderBar(
                title: book?.name ?? 'Book',
                pageLabel: _pageLabel(mode, page, total, spread),
                palette: palette,
                mode: mode,
                onModeChanged: (ReadingMode next) =>
                    setState(() => _mode = next),
                onClose: () => context.pop(),
              ),
            Expanded(
              child: switch (mode) {
                ReadingMode.verticalScroll => ReaderVerticalView(
                  bookId: widget.bookId,
                  pages: pages,
                  initialPage: page,
                  palette: palette,
                  onPageChanged: (int p) => _setPage(p, total, prefetch: false),
                  onToggleChrome: () =>
                      setState(() => _chromeVisible = !_chromeVisible),
                ),
                _ => ReaderPagedView(
                  bookId: widget.bookId,
                  pages: pages,
                  spread: spread,
                  rightToLeft: rightToLeft,
                  palette: palette,
                  onTurn: (int delta) =>
                      _turn(delta, total, mode, spreadIndex, spreads),
                  onToggleChrome: () =>
                      setState(() => _chromeVisible = !_chromeVisible),
                ),
              },
            ),
            if (_chromeVisible)
              ReaderControls(
                pagesCount: total,
                palette: palette,
                onPrevious: canGoBack
                    ? () => _turn(-1, total, mode, spreadIndex, spreads)
                    : null,
                onNext: canGoForward
                    ? () => _turn(1, total, mode, spreadIndex, spreads)
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}
