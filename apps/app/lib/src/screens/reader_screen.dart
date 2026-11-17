import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/widgets/page_navigator_sheet.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_native/src/widgets/reader_settings_sheet.dart';
import 'package:komga_native/src/widgets/reader_vertical_view.dart';
import 'package:komga_platform/komga_platform.dart';
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
/// - 本类只做**编排**——当前页、模式解析、进度回写、生命周期；
/// - 绘制在 `ReaderPagedView` / `ReaderVerticalView`；
/// - 设置面板在 `ReaderSettingsSheet`（模式/亮度/常亮/跳页，落盘到 `ReaderPrefsStore`）；
/// - 几何在 `komga_reader_engine`（纯函数，单测覆盖）。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    required this.bookId,
    this.book,
    this.direction = ReadingDirection.unknown,
    this.onOpenNext,
    super.key,
  });

  final String bookId;

  /// 从系列详情带过来的书；深链时为空，用 [readerBookProvider] 现取。
  final Book? book;

  final ReadingDirection direction;

  /// "下一本"的打开方式。
  ///
  /// 生产环境不传：阅读器自己用 go_router 替换当前页（返回仍是系列详情）。
  /// 测试传回调，避免为了一个按钮把整棵路由搬进 widget 测试。
  final void Function(Book next)? onOpenNext;

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

  /// 设置面板里的"跳页"：纵向模式靠 token 变化触发滚动跳转。
  int _jumpToken = 0;
  int _jumpPage = 1;

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

  ReadingMode _modeFor(ReaderPrefs prefs) =>
      prefs.mode.resolve(widget.direction);

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
      // 先落盘再提交：断网/切后台都不会丢这一页（见 ADR 0002）。
      await ref
          .read(progressSyncProvider)
          .save(
            widget.bookId,
            page: page,
            completed: _isCompleted(page: page, total: total),
          );
      _lastSaved = page;
    } on ShelfFailure {
      // 连本地库都写不进去才会走到这里（磁盘满/库损坏）；阅读不因此中断。
    }
  }

  /// 是否已经读到结尾。
  ///
  /// 双页模式下"最后一屏"可能包含倒数两页，此时 `page` 到不了 `total`，
  /// 只看页码会漏掉 `completed`，进度条永远差一页。
  bool _isCompleted({required int page, required int total}) {
    if (page >= total) return true;
    final mode = _modeFor(ref.read(readerPrefsProvider));
    if (mode != ReadingMode.doublePage) return false;
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

  /// 缩略图跳页：选中后走和设置面板跳页同一条路径（纵向模式也要滚动过去）。
  void _openPages({
    required ReaderPalette palette,
    required int page,
    required int total,
  }) {
    unawaited(
      showPageNavigator(
        context,
        bookId: widget.bookId,
        total: total,
        currentPage: page,
        palette: palette,
        onJump: (int target) => _jumpToPage(target, total),
      ),
    );
  }

  /// 打开下一本：**替换**当前页而不是压栈。
  ///
  /// 压栈的话连读十本要按十次返回才能回系列；替换后"读完一本 → 下一本"始终是
  /// "系列 → 当前这本"的两层结构。
  void _openNext(Book next) {
    final handler = widget.onOpenNext;
    if (handler != null) {
      handler(next);
      return;
    }
    context.pushReplacement(
      '/reader/${next.id}',
      extra: ReaderArgs(book: next, direction: widget.direction),
    );
  }

  /// 设置面板里跳到某页：单页/双页直接换页，纵向模式额外发一次滚动跳转。
  void _jumpToPage(int page, int total) {
    final target = page.clamp(1, total);
    setState(() {
      _page = target;
      _jumpPage = target;
      _jumpToken++;
    });
    _prefetch(target, total);
    _scheduleSave(target, total);
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

  String _pageLabel(
    AppLocalizations l10n,
    ReadingMode mode,
    int page,
    int total,
    List<int> spread,
  ) {
    if (mode == ReadingMode.doublePage && spread.length > 1) {
      return l10n.readerSpreadOf(spread.first + 1, spread.last + 1, total);
    }
    return l10n.readerPageOf(page, total);
  }

  Future<void> _openSettings({
    required ReaderPalette palette,
    required int page,
    required int total,
  }) {
    return showReaderSettingsSheet(
      context,
      palette: palette,
      page: page,
      total: total,
      onJump: (int target) => _jumpToPage(target, total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = ReaderPalette.of(
      isEink: ref.watch(settingsProvider).forceEink,
    );
    final prefs = ref.watch(readerPrefsProvider);
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
        title: l10n.readerNoPages,
        onRetry: () => ref.invalidate(readerPagesProvider(widget.bookId)),
      );
    }

    final total = pages.length;
    final mode = _modeFor(prefs);
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

    final completed = _isCompleted(page: page, total: total);
    // 只在完成态查"下一本"：没读完时多一次列表请求纯属浪费。
    final nextBook = completed && book != null
        ? ref
              .watch(
                nextBookProvider((seriesId: book.seriesId, bookId: book.id)),
              )
              .value
        : null;

    return WakeLockScope(
      enabled: prefs.keepAwake,
      child: Scaffold(
        backgroundColor: palette.background,
        body: Stack(
          children: <Widget>[
            SafeArea(
              child: Column(
                children: <Widget>[
                  if (_chromeVisible)
                    ValueListenableBuilder<bool>(
                      valueListenable: ref.watch(offlineProvider),
                      builder:
                          (BuildContext context, bool offline, Widget? _) =>
                              ReaderBar(
                                title: book?.name ?? l10n.readerBookFallback,
                                pageLabel: _pageLabel(
                                  l10n,
                                  mode,
                                  page,
                                  total,
                                  spread,
                                ),
                                palette: palette,
                                mode: mode,
                                offline: offline,
                                onOpenPages: () => _openPages(
                                  palette: palette,
                                  page: page,
                                  total: total,
                                ),
                                onOpenSettings: () => _openSettings(
                                  palette: palette,
                                  page: page,
                                  total: total,
                                ),
                                onClose: () => context.pop(),
                              ),
                    ),
                  Expanded(
                    child: switch (mode) {
                      ReadingMode.verticalScroll => ReaderVerticalView(
                        bookId: widget.bookId,
                        pages: pages,
                        initialPage: page,
                        jumpToken: _jumpToken,
                        jumpPage: _jumpPage,
                        palette: palette,
                        onPageChanged: (int p) =>
                            _setPage(p, total, prefetch: false),
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
                  if (_chromeVisible && completed)
                    ReaderFinishedBar(
                      palette: palette,
                      nextBook: nextBook,
                      onNext: nextBook == null
                          ? null
                          : () => _openNext(nextBook),
                      onBack: () => context.pop(),
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
            // 亮度遮罩：盖住整块阅读区（含 chrome），但不吃点击——
            // 调暗是为了少看光线，不是为了挡住操作。
            if (prefs.dimOpacity > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    key: const Key('reader-dimmer'),
                    color: Colors.black.withValues(alpha: prefs.dimOpacity),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 把"屏幕常亮"和阅读器的生命周期绑在一起：进来置真、退出置假。
///
/// 单独成 widget 而不是在 State 里手写，是为了"进入/退出/切换"三个时机
/// 都由同一个地方负责，测试里替换 [wakeLockProvider] 就能断言。
class WakeLockScope extends ConsumerStatefulWidget {
  const WakeLockScope({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  @override
  ConsumerState<WakeLockScope> createState() => _WakeLockScopeState();
}

class _WakeLockScopeState extends ConsumerState<WakeLockScope> {
  late final WakeLock _wakeLock = ref.read(wakeLockProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_wakeLock.setEnabled(widget.enabled));
  }

  @override
  void didUpdateWidget(WakeLockScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) {
      unawaited(_wakeLock.setEnabled(widget.enabled));
    }
  }

  @override
  void dispose() {
    // 离开阅读器一定放开：否则用户切到书架后屏幕永远不睡。
    unawaited(_wakeLock.setEnabled(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
