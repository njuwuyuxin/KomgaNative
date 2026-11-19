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
import 'package:komga_native/src/data/reading_session_tracker.dart';
import 'package:komga_native/src/data/shelf_failure.dart';
import 'package:komga_native/src/screens/reader_args.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/providers/reading_history_provider.dart';
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

part 'reader_screen_derive.dart';

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
    with WidgetsBindingObserver, _ReaderDerive {
  /// 进度回写：连续翻页时只写最后停下的那一页；先落盘再提交（ADR 0002）。

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 阅读会话从这里开始计时（HIS-01）。起点页码用书自带的进度，
    // 页列表还没回来也不影响——`_setPage` 之后会把 endPage 更新上去。
    _session.start(page: widget.book?.readProgress?.page ?? 1);
    _recorder = ref.read(readingSessionRecorderProvider);
    startSessionTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    // 退出阅读器时结算本次会话（HIS-01）。`ref` 在 dispose 里不能再用，
    // 所以 recorder 在 initState 就取好了。
    stopSessionTicker();
    _settleSession(completed: false);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocus.dispose();
    _progress.dispose();
    super.dispose();
  }

  /// 音量键在整个阅读器期间都归阅读器（包括页列表还在加载时）。
  @override
  Widget build(BuildContext context) {
    final isEink = ref.watch(effectiveEinkProvider);
    // 方向每次 build 重新解析（系列详情可能晚到），事件回调读这个缓存。
    _direction = _resolveDirection();
    // 偏好与书都在**本 build** 里 watch：写在 gate 的 builder 里时，
    // 偏好恢复/换书不一定会让这一层重建（RDR-05 踩到过）。
    final prefs = _effectivePrefs(ref.watch(readerPrefsProvider));
    final book =
        widget.book ?? ref.watch(readerBookProvider(widget.bookId)).value;
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
                  _buildPages(context, isEink, pages, prefs, book),
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

  Widget _buildPages(
    BuildContext context,
    bool isEink,
    List<PageInfo> pages,
    ReaderPrefs prefs,
    Book? book,
  ) {
    final l10n = AppLocalizations.of(context);
    final total = pages.length;
    _landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    // 平板默认排版（PLT-02）只看窗口宽度类，和书架两栏同一个断点。
    _tablet =
        WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.expanded;
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
    final rightToLeft = prefs.direction.resolveRightToLeft(_direction);
    final nextBook = _nextBookFor(layout, book);

    final readerBar = ReaderTopBar(
      bookId: widget.bookId,
      seriesId: book?.seriesId,
      title: book?.name ?? l10n.readerBookFallback,
      pageLabel: _pageLabelWithSession(layout.pageLabel(l10n), l10n),
      palette: palette,
      mode: mode,
      page: page,
      total: total,
      direction: _direction,
      onJump: (int t) => _jumpToPage(t, total),
      onGroupFrom: mode == ReadingMode.doublePage
          ? (int p) => _groupFromPage(p, total)
          : null,
      incognito: _incognito,
      onToggleIncognito: _toggleIncognito,
      onSharePage: () => unawaited(_sharePage(page)),
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
        // 自动滚动（RDR-08）：墨水屏不启用——每次滚动都是整屏刷新。
        autoScrollSpeed: prefs.autoScrollSpeed,
        autoScrollAllowed: !isEink,
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
          choice: prefs.pageTurn,
          eink: isEink,
          disableAnimations:
              MediaQuery.maybeDisableAnimationsOf(context) ?? false,
          // 时长走 token（墨水屏 / 减少动态效果时 token 自己会压成 0）。
          duration: AppMotion.of(context).emphasized,
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
}
