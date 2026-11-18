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
import 'package:komga_native/src/widgets/page_curl.dart';
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

  /// 往前预取几屏（双页模式一屏两页）。
  ///
  /// 4 屏 ≈ 单页 4 页 / 双页 8 页：一页看 1 秒的人也有 4 秒以上缓冲，
  /// 不会翻两下就撞上"还没加载好"的转圈。再多就开始抢当前页的带宽了。
  static const int _preloadAheadScreens = 4;

  /// 往后预取几屏：回翻也常见，但优先级低于往前。
  static const int _preloadBehindScreens = 2;

  /// 预解码几屏。
  ///
  /// 解码结果占的是 `ImageCache` 的 100 MB 预算（一张 1500×2200 约 13 MB），
  /// 所以比"抓字节"浅一档：只保证最近要看的这几屏翻过去首帧就有像素。
  static const int _decodeAheadScreens = 2;

  /// 预取时最多同时飞几张页图。
  ///
  /// 一起发太多会把"真正要显示的那一页"挤到队尾，弱网下反而更慢；
  /// 排队的其余页会在前面的回来之后接着发（`_pumpPreload`），不会丢。
  static const int _preloadConcurrency = 4;

  /// 正在预取的页（1 基），用来限流和去重。
  final Set<int> _preloading = <int>{};

  /// 还没轮到发的预取任务，按优先级（越近越前）。
  final List<({int page, bool decode})> _preloadQueue =
      <({int page, bool decode})>[];

  /// 已经排过预取的锚点：`第几页:模式`。模式变了分屏就变了，必须重排。
  String? _preloadAnchor;

  /// 已经排进下一帧、还没执行的预取。
  bool _preloadScheduled = false;

  /// 1 基当前页；0 表示"还没翻过页"，此时用服务端进度恢复位置。
  int _page = 0;
  int _lastSaved = 0;
  bool _chromeVisible = true;
  Timer? _saveTimer;

  /// 设置面板里的"跳页"：纵向模式靠 token 变化触发滚动跳转。
  int _jumpToken = 0;
  int _jumpPage = 1;

  /// 单页/双页绘制层：翻页动画由它负责，外部翻页也要经过它。
  final GlobalKey<ReaderPagedViewState> _pagedKey =
      GlobalKey<ReaderPagedViewState>();

  /// 音量键翻页：订阅在 initState，取消在 dispose。
  StreamSubscription<PageTurnKey>? _volumeKeys;

  /// dispose 里不能再碰 `ref`（widget 已卸载），所以 initState 先存一份。
  HardwareKeys? _hardwareKeys;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final hardwareKeys = ref.read(hardwareKeysProvider);
    _hardwareKeys = hardwareKeys;
    // 只有阅读器在前台时，原生侧才消费音量键；退出时立刻交还系统。
    unawaited(hardwareKeys.setActive(true));
    _volumeKeys = hardwareKeys.volumeKeys.listen(_onVolumeKey);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_hardwareKeys?.setActive(false));
    _volumeKeys?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }

  /// 音量上 = 上一页，音量下 = 下一页（阅读顺序，不跟着 RTL 反转）。
  ///
  /// 纵向模式直接忽略：滚动由 ListView 负责，再按键翻页会跟滚动位置打架。
  /// 页数据还没到时也忽略——此时 `_turn` 没有 total 可用。
  void _onVolumeKey(PageTurnKey key) {
    if (!mounted) return;
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
    if (pages == null || pages.isEmpty) return;
    final mode = _modeFor(ref.read(readerPrefsProvider));
    if (mode == ReadingMode.verticalScroll) return;
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
    } on Object {
      // 本地库打不开（磁盘满/库损坏/测试环境没有 path_provider 通道）也
      // 不能把阅读打断：这一页只是没落盘，下一次翻页会再试。
      // 只吞不报是因为进度回写是后台行为，用户此刻只想看书。
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

  /// 排一次"当前页附近"的预取。
  ///
  /// 不在 `build` 里直接发请求：build 只该读状态；而且晚一帧再发也保证
  /// 当前页自己的请求先出去——弱网下出场顺序就是优先级。
  void _schedulePreload(int page, ReadingMode mode) {
    final anchor = '$page:${mode.name}';
    if (_preloadAnchor == anchor) return;
    _preloadAnchor = anchor;
    if (_preloadScheduled) return;
    _preloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadScheduled = false;
      if (mounted) _preloadAround();
    });
  }

  /// 预取当前页前后几屏。
  ///
  /// 双页模式下"一屏"是两页，所以计划按分屏算（`preloadPlan`），
  /// 而不是 `page ± 1`——那样会一直漏掉每屏的第二页。
  void _preloadAround() {
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
    if (pages == null || pages.isEmpty) return;
    final mode = _modeFor(ref.read(readerPrefsProvider));
    // 纵向模式由 `ListView.cacheExtent` 自己预取，这里再叠一层只会重复请求。
    if (mode == ReadingMode.verticalScroll) return;

    final total = pages.length;
    final page = _resolvePage(total);
    final groups = mode == ReadingMode.doublePage
        ? _spreadsFor(pages, mode)
        : const <List<int>>[];

    // 字节：往前 4 屏、往后 2 屏。阅读快的人也不会翻两下就撞上转圈。
    final bytesPlan = preloadPlan(
      pageIndex: page - 1,
      pageCount: total,
      spreads: groups,
      ahead: _preloadAheadScreens,
      behind: _preloadBehindScreens,
    );
    // 位图：解码占的是 ImageCache 的预算，比抓字节浅一档。
    final decodePlan = preloadPlan(
      pageIndex: page - 1,
      pageCount: total,
      spreads: groups,
      ahead: _decodeAheadScreens,
      behind: 0,
    ).toSet();

    // 整份计划重新排队：还没发的旧计划作废（分屏/位置可能已经变了），
    // 已经在飞的不受影响。
    _preloadQueue
      ..clear()
      ..addAll(<({int page, bool decode})>[
        for (final index in bytesPlan)
          (page: index + 1, decode: decodePlan.contains(index)),
      ]);
    _pumpPreload();
  }

  /// 按并发上限从队列里发预取。
  ///
  /// 之前是"超上限的直接丢"，结果是阅读快时计划尾部永远轮不到；
  /// 改成排队后，前一个回来就补下一个，最多慢一点但不会漏。
  void _pumpPreload() {
    while (_preloading.length < _preloadConcurrency &&
        _preloadQueue.isNotEmpty) {
      final next = _preloadQueue.removeAt(0);
      if (_preloading.contains(next.page)) continue;
      unawaited(_preload(next.page, decode: next.decode));
    }
  }

  /// 预取一页：抓字节暖仓库 LRU；[decode] 为真时顺手把位图解码进 ImageCache。
  ///
  /// 只暖字节是不够的——`Image` 要等解码完才有像素，那段空档就是用户看到的
  /// "翻页时闪一下黑"。解码过之后翻过去的第一帧就有图。
  ///
  /// 失败静默：真翻到那一页时会重新请求，走正常的错误/重试路径。
  Future<void> _preload(int page, {required bool decode}) async {
    if (!_preloading.add(page)) return;
    try {
      final bytes = await ref
          .read(readerRepositoryProvider)
          .pageImage(widget.bookId, page);
      if (!decode || !mounted) return;
      unawaited(
        precacheImage(
          MemoryImage(bytes),
          context,
          onError: (Object error, StackTrace? stackTrace) {},
        ),
      );
    } on ShelfFailure {
      // 预取失败不影响阅读。
    } finally {
      _preloading.remove(page);
      if (mounted) _pumpPreload();
    }
  }

  void _setPage(int page, int total) {
    if (page == _page) return;
    setState(() => _page = page);
    // 预取不在各个入口各写一遍：`build` 里的 `_schedulePreload` 会看到
    // 页码/模式变化并重排，翻页、跳页、切模式走的是同一条路。
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

  /// 相邻那一屏的页索引；到书头/书尾返回 null。
  ///
  /// 翻页动画需要它：拖动时先把相邻那一屏画在下面，翻过去才真正换页。
  List<int>? _neighbourSpread(
    int delta,
    ReadingMode mode,
    List<List<int>> spreads,
    int spreadIndex,
    int page,
    int total,
  ) {
    if (mode == ReadingMode.doublePage && spreads.isNotEmpty) {
      final index = spreadIndex + delta;
      if (index < 0 || index >= spreads.length) return null;
      return spreads[index];
    }
    final target = page + delta;
    if (target < 1 || target > total) return null;
    return <int>[target - 1];
  }

  /// 翻页动效：墨水屏和"系统关闭动画"直接不做动画；单页、双页都卷页
  /// （单页↔双页交界那一下由 `ReaderPagedView` 自己退化成平移）。
  PageTurnStyle _turnStyle() {
    if (ref.watch(settingsProvider).forceEink) {
      return const PageTurnStyle(effect: PageTurnEffect.none);
    }
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return const PageTurnStyle(effect: PageTurnEffect.none);
    }
    return const PageTurnStyle();
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

  /// 底栏的页码：只报"当前在第几页"。
  ///
  /// 以前这里显示总页数（`{count} pages`），翻页时永远不变，看起来像页码坏了；
  /// 总数已经在顶栏的 `3 / 12` 里，底栏再说一遍只会让人误以为页码没跟上。
  String _positionLabel(
    AppLocalizations l10n,
    ReadingMode mode,
    int page,
    List<int> spread,
  ) {
    if (mode == ReadingMode.doublePage && spread.length > 1) {
      return l10n.currentSpread(spread.first + 1, spread.last + 1);
    }
    return l10n.currentPage(page);
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
    // 打开、翻页、跳页、切模式都会经过这里：页码/模式变了就在下一帧重排预取。
    _schedulePreload(page, mode);
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
    final nextSpread = _neighbourSpread(
      1,
      mode,
      spreads,
      spreadIndex,
      page,
      total,
    );
    final previousSpread = _neighbourSpread(
      -1,
      mode,
      spreads,
      spreadIndex,
      page,
      total,
    );

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
                        onPageChanged: (int p) => _setPage(p, total),
                        onToggleChrome: () =>
                            setState(() => _chromeVisible = !_chromeVisible),
                      ),
                      _ => ReaderPagedView(
                        key: _pagedKey,
                        bookId: widget.bookId,
                        pages: pages,
                        spread: spread,
                        rightToLeft: rightToLeft,
                        palette: palette,
                        nextSpread: nextSpread,
                        previousSpread: previousSpread,
                        style: _turnStyle(),
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
                      pageLabel: _positionLabel(l10n, mode, page, spread),
                      palette: palette,
                      // 点击区与底部箭头共用这一个判断：RTL 时左侧（点/箭头）
                      // 都是"下一页"。后续加"阅读方向"设置时只改这里的来源。
                      leftTurnsNext: rightToLeft,
                      onPrevious: canGoBack
                          ? () => _requestTurn(-1, mode)
                          : null,
                      onNext: canGoForward ? () => _requestTurn(1, mode) : null,
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
