import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/reader_prefs.dart';
import 'package:komga_native/src/screens/reader_args.dart';
import 'package:komga_native/src/providers/progress_providers.dart';
import 'package:komga_native/src/providers/reader_prefs_provider.dart';
import 'package:komga_native/src/providers/reader_providers.dart';
import 'package:komga_native/src/providers/settings_provider.dart';
import 'package:komga_native/src/widgets/page_curl.dart';
import 'package:komga_native/src/widgets/reader_chrome.dart';
import 'package:komga_native/src/widgets/reader_frame.dart';
import 'package:komga_native/src/widgets/reader_layout.dart';
import 'package:komga_native/src/widgets/reader_pages_gate.dart';
import 'package:komga_native/src/widgets/reader_paged_view.dart';
import 'package:komga_native/src/widgets/reader_palette.dart';
import 'package:komga_native/src/widgets/reader_preloader.dart';
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

  /// 设置面板里的"跳页"：纵向模式靠 token 变化触发滚动跳转。
  int _jumpToken = 0;
  int _jumpPage = 1;

  /// 单页/双页绘制层：翻页动画由它负责，外部翻页也要经过它。
  final GlobalKey<ReaderPagedViewState> _pagedKey =
      GlobalKey<ReaderPagedViewState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    super.dispose();
  }

  /// 音量上 = 上一页，音量下 = 下一页（阅读顺序，不跟着 RTL 反转）。
  ///
  /// 纵向模式直接忽略：滚动由 ListView 负责，再按键翻页会跟滚动位置打架。
  /// 页数据还没到时也忽略——此时 `_turn` 没有 total 可用。
  void _onVolumeKey(PageTurnKey key) {
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
    if (pages == null || pages.isEmpty) return;
    final mode = _modeFor(ref.read(readerPrefsProvider));
    _requestTurn(key == PageTurnKey.next ? 1 : -1, mode);
  }

  /// 外部翻页（底栏箭头 / 音量键）统一入口。
  ///
  /// 单页/双页交给绘制层播动画，动画结束后它再回调 `onTurn` 真正换页；
  /// 绘制层还没建好时（页数据未到）什么也不做。
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
    unawaited(_progress.flush(_resolvePage(total)));
  }

  ReadingMode _modeFor(ReaderPrefs prefs) =>
      prefs.mode.resolve(widget.direction);

  /// 用当前状态现算一份布局；页数据还没到时为 null。
  ReaderLayout? _currentLayout() {
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
    if (pages == null || pages.isEmpty) return null;
    return ReaderLayout(
      pages: pages,
      mode: _modeFor(ref.read(readerPrefsProvider)),
      page: _resolvePage(pages.length),
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
    // 预取不在各个入口各写一遍：`build` 里的 `_schedulePreload` 会看到
    // 页码/模式变化并重排，翻页、跳页、切模式走的是同一条路。
    _progress.schedule(page);
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

  /// 跳到某页（设置面板 / 缩略图）：单页/双页直接换页，纵向模式额外发一次滚动跳转。
  void _jumpToPage(int page, int total) {
    final target = page.clamp(1, total);
    setState(() {
      _page = target;
      _jumpPage = target;
      _jumpToken++;
    });
    _progress.schedule(target);
  }

  /// 翻页动效：墨水屏和"系统关闭动画"直接不做动画；单页、双页都卷页
  /// （单页↔双页交界那一下由 `ReaderPagedView` 自己退化成平移）。
  PageTurnStyle _turnStyle() {
    if (ref.watch(settingsProvider).forceEink ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return const PageTurnStyle(effect: PageTurnEffect.none);
    }
    return const PageTurnStyle();
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  /// 音量键在整个阅读器期间都归阅读器（包括页列表还在加载时）。
  @override
  Widget build(BuildContext context) =>
      VolumeKeyScope(onKey: _onVolumeKey, child: _buildReader(context));

  Widget _buildReader(BuildContext context) {
    final palette = ReaderPalette.of(
      isEink: ref.watch(settingsProvider).forceEink,
    );
    return ReaderPagesGate(
      pages: ref.watch(readerPagesProvider(widget.bookId)),
      palette: palette,
      onRetry: () => ref.invalidate(readerPagesProvider(widget.bookId)),
      builder: (List<PageInfo> pages) => _buildPages(context, palette, pages),
    );
  }

  Widget _buildPages(
    BuildContext context,
    ReaderPalette palette,
    List<PageInfo> pages,
  ) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(readerPrefsProvider);
    final book =
        widget.book ?? ref.watch(readerBookProvider(widget.bookId)).value;
    final total = pages.length;
    final layout = ReaderLayout(
      pages: pages,
      mode: _modeFor(prefs),
      page: _resolvePage(total),
    );
    final mode = layout.mode;
    final page = layout.page;
    // 打开、翻页、跳页、切模式都会经过这里：页码/模式变了就在下一帧重排预取。
    _schedulePreload(page, mode);
    final rightToLeft = widget.direction.isRightToLeft;
    final completed = layout.completed;
    // 只在完成态查"下一本"：没读完时多一次列表请求纯属浪费。
    final nextBook = completed && book != null
        ? ref
              .watch(
                nextBookProvider((seriesId: book.seriesId, bookId: book.id)),
              )
              .value
        : null;

    final readerBar = ReaderTopBar(
      bookId: widget.bookId,
      title: book?.name ?? l10n.readerBookFallback,
      pageLabel: layout.pageLabel(l10n),
      palette: palette,
      mode: mode,
      page: page,
      total: total,
      onJump: (int t) => _jumpToPage(t, total),
    );
    final content = switch (mode) {
      ReadingMode.verticalScroll => ReaderVerticalView(
        bookId: widget.bookId,
        pages: pages,
        initialPage: page,
        jumpToken: _jumpToken,
        jumpPage: _jumpPage,
        palette: palette,
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
        nextSpread: layout.neighbour(1),
        previousSpread: layout.neighbour(-1),
        style: _turnStyle(),
        onTurn: (int delta) {
          final target = layout.turnTarget(delta);
          if (target != null) _setPage(target, total);
        },
        onToggleChrome: _toggleChrome,
      ),
    };

    return WakeLockScope(
      enabled: prefs.keepAwake,
      child: ReaderFrame(
        palette: palette,
        chromeVisible: _chromeVisible,
        dimOpacity: prefs.dimOpacity,
        topBar: readerBar,
        content: content,
        finishedBar: completed
            ? ReaderFinishedBar(
                palette: palette,
                nextBook: nextBook,
                onNext: nextBook == null ? null : () => _openNext(nextBook),
                onBack: () => context.pop(),
              )
            : null,
        bottomBar: ReaderControls(
          pageLabel: layout.positionLabel(l10n),
          palette: palette,
          // 点击区与底部箭头共用这一个判断：RTL 时左侧（点/箭头）
          // 都是"下一页"。后续加"阅读方向"设置时只改这里的来源。
          leftTurnsNext: rightToLeft,
          onPrevious: layout.canGoBack ? () => _requestTurn(-1, mode) : null,
          onNext: layout.canGoForward ? () => _requestTurn(1, mode) : null,
        ),
      ),
    );
  }
}
