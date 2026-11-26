import 'dart:async';

import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/page_save.dart';
import 'package:yomu/src/data/page_share.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/data/reading_session_tracker.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/screens/reader_args.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/series_read_provider.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/widgets/edge_swipe_back.dart';
import 'package:yomu/src/widgets/page_curl.dart';
import 'package:yomu/src/widgets/reader_background.dart';
import 'package:yomu/src/widgets/reader_bottom_chrome.dart';
import 'package:yomu/src/widgets/reader_frame.dart';
import 'package:yomu/src/widgets/reader_layout.dart';
import 'package:yomu/src/widgets/reader_opening_hero.dart';
import 'package:yomu/src/widgets/reader_pages_gate.dart';
import 'package:yomu/src/widgets/reader_paged_view.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_preloader.dart';
import 'package:yomu/src/widgets/reader_system_ui.dart';
import 'package:yomu/src/widgets/reader_top_bar.dart';
import 'package:yomu/src/widgets/reader_progress_writer.dart';
import 'package:yomu/src/widgets/reader_vertical_view.dart';
import 'package:yomu/src/widgets/volume_key_scope.dart';
import 'package:yomu/src/widgets/wake_lock_scope.dart';
import 'package:yomu_platform/yomu_platform.dart';
import 'package:yomu_reader/yomu_reader.dart';
import 'package:material_ui/material_ui.dart';

export 'package:yomu/src/screens/reader_args.dart';
export 'package:yomu/src/widgets/wake_lock_scope.dart';

part 'reader_screen_derive.dart';
part 'reader_screen_actions.dart';

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
    with WidgetsBindingObserver, _ReaderDerive, _ReaderActions {
  /// 进度回写：连续翻页时只写最后停下的那一页；先落盘再提交（ADR 0002）。

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 阅读会话与进度收尾服务在 initState 预取（dispose 里不能再碰 ref）。
    _session.start(page: widget.book?.readProgress?.page ?? 1);
    final activeKey = ref.read(activeServerKeyProvider);
    _bookScope = widget.bookId.startsWith('local:')
        ? kLocalSourceKey
        : ((widget.book?.isCloud ?? false)
              ? widget.book!.sourceKey
              : activeKey);
    _recorder = ref.read(readingSessionRecorderProvider);
    _progressSync = ref.read(progressSyncProvider);
    _committer = ref.read(readerProgressCommitterProvider);
    startSessionTicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    stopSessionTicker();
    _settleSession(completed: false);
    _settleProgressOnLeave();
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
    final allPrefs = ref.watch(readerPrefsProvider);
    final serverKey = ref.watch(activeServerKeyProvider);
    final book =
        widget.book ?? ref.watch(readerBookProvider(widget.bookId)).value;
    final config = allPrefs.forSeries(
      book?.seriesId ?? _seriesId,
      serverKey: serverKey,
    );
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final openingHero = widget.heroTag;
    return PopScope(
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) _settleProgressOnLeave();
      },
      child: EdgeSwipeBack(
        child: VolumeKeyScope(
          onKey: _onVolumeKey,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ReaderPagesGate(
                pages: ref.watch(readerPagesProvider(widget.bookId)),
                palette: ReaderPalette.of(isEink: isEink),
                onRetry: () =>
                    ref.invalidate(readerPagesProvider(widget.bookId)),
                builder: (List<PageInfo> pages) => _buildPages(
                  context,
                  isEink,
                  pages,
                  allPrefs.tabletLayout,
                  config,
                  book,
                ),
              ),
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
      ),
    );
  }

  Widget _buildPages(
    BuildContext context,
    bool isEink,
    List<PageInfo> pages,
    TabletLayoutChoice tabletLayout,
    ReaderConfig config,
    Book? book,
  ) {
    final l10n = AppLocalizations.of(context);
    final total = pages.length;
    _landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    // 平板默认排版（PLT-02）只看窗口宽度类，和书架两栏同一个断点。
    _tablet =
        WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.expanded;
    final rightToLeft = config.direction.resolveRightToLeft(_direction);
    final layout = _buildLayout(pages, tabletLayout, config);
    _noteBookAndLayout(book, layout);
    final palette = resolveReaderPalette(
      isEink: isEink,
      config: config,
      layout: layout,
      ref: ref,
      bookId: widget.bookId,
    );
    final mode = layout.mode;
    final page = layout.page;
    _schedulePreload(page, mode);
    final nextBook = _nextBookFor(layout, book);

    final readerBar = ReaderTopBar(
      bookId: widget.bookId,
      seriesId: book?.seriesId,
      title: book?.name ?? l10n.readerBookFallback,
      pageLabel: _pageLabelWithSession(
        layout.pageLabel(l10n),
        l10n,
        showSessionTime: config.showSessionTime,
      ),
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
      onSavePage: () => unawaited(_saveScreenImage(layout, rightToLeft)),
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
        trimBorders: config.trimBorders,
        // 自动滚动（RDR-08）：墨水屏不启用——每次滚动都是整屏刷新。
        autoScrollSpeed: config.autoScrollSpeed,
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
        fit: config.fit.fit,
        doublePage: mode == ReadingMode.doublePage,
        lockZoom: config.lockZoom,
        trimBorders: config.trimBorders,
        tapZone: config.tapZone,
        invertTapZones: config.invertTapZones,
        doubleTapZoom: config.doubleTapZoom,
        nextSpread: layout.neighbour(1),
        previousSpread: layout.neighbour(-1),
        pageHalf: layout.currentFrameHalf,
        nextPageHalf: layout.splitNeighbour(1)?.half ?? PageHalf.full,
        previousPageHalf: layout.splitNeighbour(-1)?.half ?? PageHalf.full,
        style: PageTurnStyle.resolve(
          choice: config.pageTurn,
          eink: isEink,
          disableAnimations:
              MediaQuery.maybeDisableAnimationsOf(context) ?? false,
          duration: AppMotion.of(context).emphasized,
        ),
        onTurn: (int delta) => _handlePagedTurn(layout, delta, total, nextBook),
        onToggleChrome: _toggleChrome,
      ),
    };

    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: WakeLockScope(
        enabled: config.keepAwake,
        child: ReaderSystemUi(
          immersive: !_chromeVisible,
          child: ReaderFrame(
            palette: palette,
            chromeVisible: _chromeVisible,
            dimOpacity: config.dimOpacity,
            floatingAction: layout.canToggleTempMerge
                ? ReaderTempMergePill(
                    merged: layout.isTempMerged,
                    label: layout.isTempMerged
                        ? l10n.readerTempSplitSpread
                        : l10n.readerTempMergeSpread,
                    palette: palette,
                    onPressed: () => _toggleTempMerge(page - 1),
                  )
                : null,
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
