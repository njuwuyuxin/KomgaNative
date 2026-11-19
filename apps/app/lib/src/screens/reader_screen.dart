import 'dart:async';

import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/page_share.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/screens/reader_args.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/widgets/edge_swipe_back.dart';
import 'package:komga_native/src/widgets/page_curl.dart';
import 'package:komga_native/src/widgets/reader_background.dart';
import 'package:komga_native/src/widgets/reader_bottom_chrome.dart';
import 'package:komga_native/src/widgets/reader_frame.dart';
import 'package:komga_native/src/widgets/reader_layout.dart';
import 'package:komga_native/src/widgets/reader_opening_hero.dart';
import 'package:komga_native/src/widgets/reader_pages_gate.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_native/src/widgets/reader_preloader.dart';
import 'package:komga_native/src/widgets/reader_system_ui.dart';
import 'package:komga_native/src/widgets/reader_top_bar.dart';
import 'package:komga_native/src/widgets/reader_progress_writer.dart';
import 'package:komga_native/src/widgets/reader_vertical_view.dart';
import 'package:komga_native/src/widgets/volume_key_scope.dart';
import 'package:komga_native/src/widgets/wake_lock_scope.dart';
import 'package:komga_platform/komga_platform.dart';
import 'package:komga_reader_engine/komga_reader_engine.dart';
import 'package:material_ui/material_ui.dart';

export 'package:komga_native/src/screens/reader_args.dart';
export 'package:komga_native/src/widgets/wake_lock_scope.dart';

/// 漫画阅读器：单页 / 双页跨页 / 纵向连续。
///
/// 分工：
/// - 本类只做**编排**——当前页、模式解析、进度回写、生命周期；
/// - 这一屏的派生状态（分屏、能否翻页、是否读完、页码文案）在 [ReaderLayout]；
/// - 页图预取调度在 [ReaderPreloader]；
/// - 绘制在 `ReaderPagedView` / `ReaderVerticalView`；
/// - 设置面板在 `ReaderSettingsSheet`（模式/亮度/常亮/跳页，落盘到 `ReaderPrefsStore`）；
/// - 几何在 `komga_reader_engine`（纯函数，单测覆盖）。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    required this.bookId,
    this.book,
    this.direction = ReadingDirection.unknown,
    this.heroTag,
    this.onOpenNext,
    this.onSharePage,
    super.key,
  });

  final String bookId;

  /// 从系列详情带过来的书；深链时为空，用 [readerBookProvider] 现取。
  final Book? book;

  final ReadingDirection direction;

  /// 源卡片的封面 Hero tag（继续阅读卡片 → 阅读器开场，UI-P2-2）。
  final String? heroTag;

  /// "下一本"的打开方式。
  ///
  /// 生产环境不传：阅读器自己用 go_router 替换当前页（返回仍是系列详情）。
  /// 测试传回调，避免为了一个按钮把整棵路由搬进 widget 测试。
  final void Function(Book next)? onOpenNext;

  /// 分享某页的测试接缝；生产环境不传，走系统分享面板（UI-P3-6）。
  final Future<void> Function(int page)? onSharePage;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  /// 进度回写：连续翻页时只写最后停下的那一页；先落盘再提交（ADR 0002）。
  late final ReaderProgressWriter _progress = ReaderProgressWriter(
    write: (int page) => ref
        .read(progressSyncProvider)
        .save(
          widget.bookId,
          page: page,
          completed: _currentLayout()?.isCompletedAt(page) ?? false,
        ),
  );

  late final ReaderPreloader _preloader = ReaderPreloader(
    fetch: (int page) =>
        ref.read(readerRepositoryProvider).pageImage(widget.bookId, page),
    decode: (bytes) => unawaited(
      precacheImage(
        MemoryImage(bytes),
        context,
        onError: (Object error, StackTrace? stackTrace) {},
      ),
    ),
    isActive: () => mounted,
  );

  /// 1 基当前页；0 表示"还没翻过页"，此时用服务端进度恢复位置。
  int _page = 0;
  bool _chromeVisible = true;

  /// 横屏自动双页用；由 `_buildPages` 每次布局时更新（UI-P3-3）。
  bool _landscape = false;

  /// 手动修正双页分组的起点（0 基；null = 自动，UI-P3-5）。
  int? _spreadFrom;

  /// 本次阅读不回写进度（UI-P3-12）；不落盘，退出即恢复。
  bool _incognito = false;

  /// 设置面板里的"跳页"：纵向模式靠 token 变化触发滚动跳转。
  int _jumpToken = 0;
  int _jumpPage = 1;

  /// 单页/双页绘制层：翻页动画由它负责，外部翻页也要经过它。
  final GlobalKey<ReaderPagedViewState> _pagedKey =
      GlobalKey<ReaderPagedViewState>();

  /// 键盘/翻页器焦点。显式 request 一次：只靠 autofocus 在部分真机上
  /// 会被路由的焦点作用域抢走，方向键就落不到阅读器。
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'reader-keyboard');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocus.dispose();
    _progress.dispose();
    super.dispose();
  }

  /// 音量上 = 上一页，音量下 = 下一页（阅读顺序，不跟着 RTL 反转）。
  /// 纵向模式忽略：滚动交给 ListView；页数据没到时也没有 total 可用。
  void _onVolumeKey(PageTurnKey key) {
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
    if (pages == null || pages.isEmpty) return;
    final mode = _modeFor(_effectivePrefs(ref.read(readerPrefsProvider)));
    _requestTurn(key == PageTurnKey.next ? 1 : -1, mode);
  }

  /// 当前书的系列 id（按系列记忆设置用，UI-P3-2）。
  String? get _seriesId =>
      (widget.book ?? ref.read(readerBookProvider(widget.bookId)).value)
          ?.seriesId;

  /// 系列覆盖优先，其余用全局。
  ReaderPrefs _effectivePrefs(ReaderPrefs prefs) => prefs.forSeries(_seriesId);

  /// 外部翻页（底栏箭头 / 音量键）统一入口：交给绘制层播动画，动画结束后
  /// 它再回调 `onTurn` 真正换页；绘制层还没建好时（页数据未到）什么也不做。
  void _requestTurn(int delta, ReadingMode mode) {
    if (mode == ReadingMode.verticalScroll) return;
    _pagedKey.currentState?.turn(delta);
  }

  /// 切后台/锁屏时立刻落一次进度：只靠防抖会丢掉"看完就退出"的那一页。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    final total =
        ref.read(readerPagesProvider(widget.bookId)).value?.length ?? 0;
    if (total == 0) return;
    if (_incognito) return;
    unawaited(_progress.flush(_resolvePage(total)));
  }

  ReadingMode _modeFor(ReaderPrefs prefs, {bool? landscape}) =>
      prefs.mode.resolve(widget.direction, landscape: landscape ?? _landscape);

  /// 用当前状态现算一份布局；页数据还没到时为 null。
  ReaderLayout? _currentLayout() {
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
    if (pages == null || pages.isEmpty) return null;
    return ReaderLayout(
      pages: pages,
      mode: _modeFor(_effectivePrefs(ref.read(readerPrefsProvider))),
      page: _resolvePage(pages.length),
      groupFrom: _spreadFrom,
    );
  }

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

  /// 排一次"当前页附近"的预取（下一帧执行，见 [ReaderPreloader.scheduleFor]）。
  void _schedulePreload(int page, ReadingMode mode) {
    _preloader.scheduleFor('$page:${mode.name}', () {
      final layout = _currentLayout();
      // 纵向模式由 `ListView.cacheExtent` 自己预取，这里再叠一层只会重复请求。
      if (layout == null || layout.mode == ReadingMode.verticalScroll) return;
      _preloader.planAround(
        page: layout.page,
        total: layout.total,
        spreads: layout.spreads,
      );
    });
  }

  void _setPage(int page, int total) {
    if (page == _page) return;
    setState(() => _page = page);
    // 预取不用在这里排：`build` 里的 `_schedulePreload` 会看到页码变化重排。
    _scheduleProgress(page);
  }

  /// 打开下一本：**替换**当前页而不是压栈（连读十本不必按十次返回）。
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

  /// 跳到某页（设置面板 / 缩略图）：单页/双页直接换页，纵向模式额外发一次滚动跳转。
  void _jumpToPage(int page, int total) {
    final target = page.clamp(1, total);
    setState(() {
      _page = target;
      _jumpPage = target;
      _jumpToken++;
    });
    _scheduleProgress(target);
  }

  /// 分享当前页（UI-P3-6）：取页图字节 → 写临时文件 → 系统分享面板。
  Future<void> _sharePage(int page) async {
    final handler = widget.onSharePage;
    if (handler != null) {
      await handler(page);
      return;
    }
    try {
      final bytes = await ref
          .read(readerRepositoryProvider)
          .pageImage(widget.bookId, page);
      await sharePageImage(
        bytes,
        fileName: 'komganative-${widget.bookId}-page-$page.png',
      );
    } on ShelfFailure catch (failure) {
      _showShareError(failure.message);
    } on PlatformException catch (_) {
      _showShareError(AppLocalizations.of(context).sharePageFailed);
    }
  }

  void _showShareError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _scheduleProgress(int page) {
    if (_incognito) return;
    _progress.schedule(page);
  }

  /// 隐身模式：本次阅读不回写进度（UI-P3-12）。
  void _toggleIncognito() {
    setState(() => _incognito = !_incognito);
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _incognito ? l10n.incognitoEnabled : l10n.incognitoDisabled,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _groupFromPage(int page, int total) {
    final index = page.clamp(1, total) - 1;
    final next = _spreadFrom == index ? null : index;
    setState(() {
      _spreadFrom = next;
      if (next != null) _page = page.clamp(1, total);
    });
    if (next != null) _scheduleProgress(page.clamp(1, total));
    unawaited(AppHaptics.selection());
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next == null
              ? l10n.readerGroupAutomatic
              : l10n.readerGroupFrom(page.clamp(1, total)),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 只在完成态查"下一本"：没读完时多一次列表请求纯属浪费。
  Book? _nextBookFor(ReaderLayout layout, Book? book) {
    if (!layout.completed || book == null) return null;
    return ref
        .watch(nextBookProvider((seriesId: book.seriesId, bookId: book.id)))
        .value;
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  /// 音量键在整个阅读器期间都归阅读器（包括页列表还在加载时）。
  @override
  Widget build(BuildContext context) {
    final isEink = ref.watch(settingsProvider).forceEink;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final openingHero = widget.heroTag;
    return EdgeSwipeBack(
      child: VolumeKeyScope(
        onKey: _onVolumeKey,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ReaderPagesGate(
              pages: ref.watch(readerPagesProvider(widget.bookId)),
              palette: ReaderPalette.of(isEink: isEink),
              onRetry: () => ref.invalidate(readerPagesProvider(widget.bookId)),
              builder: (List<PageInfo> pages) =>
                  _buildPages(context, isEink, pages),
            ),
            // 继续阅读卡片的封面先飞进来，落地后再由页图接管（UI-P2-2）。
            // 没有源卡片、墨水屏、系统"减少动态效果"时都不建。
            if (openingHero != null && !isEink && !reduceMotion)
              Positioned.fill(
                child: ReaderOpeningHero(
                  bookId: widget.bookId,
                  page: widget.book?.readProgress?.page ?? 1,
                  tag: openingHero,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPages(BuildContext context, bool isEink, List<PageInfo> pages) {
    final l10n = AppLocalizations.of(context);
    final prefs = _effectivePrefs(ref.watch(readerPrefsProvider));
    final book =
        widget.book ?? ref.watch(readerBookProvider(widget.bookId)).value;
    final total = pages.length;
    _landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final layout = ReaderLayout(
      pages: pages,
      mode: _modeFor(prefs),
      page: _resolvePage(total),
      groupFrom: _spreadFrom,
    );
    // 配色在这一屏才算得出来：动态背景要读当前屏各页的页边主色（UI-P1-5）。
    final palette = resolveReaderPalette(
      isEink: isEink,
      prefs: prefs,
      layout: layout,
      ref: ref,
      bookId: widget.bookId,
    );
    final mode = layout.mode;
    final page = layout.page;
    // 打开、翻页、跳页、切模式都会经过这里：页码/模式变了就在下一帧重排预取。
    _schedulePreload(page, mode);
    // 阅读方向：设置优先，`auto` 时才跟随系列（UI-P1-4）。
    // 点击区、底栏箭头、缩略图滑条、卷页方向都从这一个值派生。
    final rightToLeft = prefs.direction.resolveRightToLeft(widget.direction);
    final nextBook = _nextBookFor(layout, book);

    final readerBar = ReaderTopBar(
      bookId: widget.bookId,
      seriesId: book?.seriesId,
      title: book?.name ?? l10n.readerBookFallback,
      pageLabel: layout.pageLabel(l10n),
      palette: palette,
      mode: mode,
      page: page,
      total: total,
      onJump: (int t) => _jumpToPage(t, total),
      onGroupFrom: mode == ReadingMode.doublePage
          ? (int p) => _groupFromPage(p, total)
          : null,
      incognito: _incognito,
      onToggleIncognito: _toggleIncognito,
    );
    final content = switch (mode) {
      ReadingMode.verticalScroll => ReaderVerticalView(
        bookId: widget.bookId,
        pages: pages,
        initialPage: page,
        jumpToken: _jumpToken,
        jumpPage: _jumpPage,
        palette: palette,
        trimBorders: prefs.trimBorders,
        onPageChanged: (int p) => _setPage(p, total),
        onToggleChrome: _toggleChrome,
      ),
      _ => ReaderPagedView(
        key: _pagedKey,
        bookId: widget.bookId,
        pages: pages,
        spread: layout.spread,
        rightToLeft: rightToLeft,
        palette: palette,
        fit: prefs.fit.fit,
        doublePage: mode == ReadingMode.doublePage,
        lockZoom: prefs.lockZoom,
        trimBorders: prefs.trimBorders,
        nextSpread: layout.neighbour(1),
        previousSpread: layout.neighbour(-1),
        style: PageTurnStyle.resolve(
          eink: ref.watch(settingsProvider).forceEink,
          disableAnimations:
              MediaQuery.maybeDisableAnimationsOf(context) ?? false,
        ),
        onTurn: (int delta) {
          final target = layout.turnTarget(delta);
          if (target != null) {
            _setPage(target, total);
            return;
          }
          // 到书尾还继续往回翻不了、往前翻得动：直接进下一本（Panels 的行为）。
          // 拿不到下一本时什么都不做，不报错。
          if (delta > 0 && nextBook != null) _openNext(nextBook);
        },
        onToggleChrome: _toggleChrome,
      ),
    };

    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: WakeLockScope(
        enabled: prefs.keepAwake,
        // chrome 显隐同时驱动两件事：浮层动画（ReaderFrame）与系统栏（ReaderSystemUi）。
        child: ReaderSystemUi(
          immersive: !_chromeVisible,
          child: ReaderFrame(
            palette: palette,
            chromeVisible: _chromeVisible,
            dimOpacity: prefs.dimOpacity,
            topBar: readerBar,
            content: content,
            bottomBar: ReaderBottomChrome(
              bookId: widget.bookId,
              layout: layout,
              palette: palette,
              rightToLeft: rightToLeft,
              nextBook: nextBook,
              onJump: (int p) => _jumpToPage(p, total),
              onGroupFrom: mode == ReadingMode.doublePage
                  ? (int p) => _groupFromPage(p, total)
                  : null,
              onSharePage: _sharePage,
              onOpenNext: nextBook == null ? null : () => _openNext(nextBook),
              onBack: () => context.pop(),
              onPrevious: layout.canGoBack
                  ? () => _requestTurn(-1, mode)
                  : null,
              onNext: layout.canGoForward ? () => _requestTurn(1, mode) : null,
            ),
          ),
        ),
      ),
    );
  }

  /// 键盘 / 蓝牙翻页器 / 遥控器（UI-P3-11）。
  ///
  /// 方向键与 PageUp/PageDown 走和点击区同一套 `_requestTurn`，
  /// 所以 RTL 下"右"仍然是视觉上的下一页；Esc 退出阅读器。
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
    if (pages == null || pages.isEmpty) return KeyEventResult.ignored;
    final prefs = _effectivePrefs(ref.read(readerPrefsProvider));
    final mode = _modeFor(prefs);
    final rightToLeft = prefs.direction.resolveRightToLeft(widget.direction);
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _requestTurn(rightToLeft ? -1 : 1, mode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _requestTurn(rightToLeft ? 1 : -1, mode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.space) {
      _requestTurn(1, mode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      _requestTurn(-1, mode);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      unawaited(Navigator.of(context).maybePop());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}
