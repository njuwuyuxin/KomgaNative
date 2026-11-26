part of 'reader_screen.dart';

/// 阅读器的状态与命令（QUA-01）。
///
/// 为什么用 part + mixin 而不是再拆一个 widget：这些方法要直接读写页码、
/// 分屏起点、隐身开关等私有状态，拆出去只会变成一长串回调参数。part 与宿主
/// 同属一个 library，私有成员照常可见，宿主文件也回到 350 行以内。
mixin _ReaderDerive on ConsumerState<ReaderScreen>, WidgetsBindingObserver {
  late ProgressSyncService _progressSync;
  late ReaderProgressCommitter _committer;
  String? _resolvedSourceKey;

  ReaderBookQuery get _bookQuery =>
      (sourceKey: _resolvedSourceKey, bookId: widget.bookId);

  late final ReaderProgressWriter _progress = ReaderProgressWriter(
    write: (int page) => _progressSync.save(
      widget.bookId,
      page: page,
      completed:
          ((!_settledLeave && mounted ? _currentLayout() : null) ?? _lastLayout)
              ?.isCompletedAt(page) ??
          false,
      scope: _resolvedSourceKey,
    ),
  );

  late final ReaderPreloader _preloader = ReaderPreloader(
    fetch: (int page) => ref
        .read(readerRepositoryForSourceProvider(_resolvedSourceKey))
        .pageImage(widget.bookId, page),
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

  /// 宽页自动切分时的当前半幅；null 表示进入该物理页的首个阅读半幅（LMB-01）。
  PageHalf? _pageHalf;

  /// 用户点击「合页查看」后临时合并展示整张宽图的 0 基物理页索引；翻离该页自动清空。
  int? _mergedWidePageIndex;

  bool _chromeVisible = true;

  /// 最近一次布局与书元信息缓存：供退出阅读器（`dispose` 不能碰 `ref`）时落盘。
  ReaderLayout? _lastLayout;
  Book? _lastBook;
  bool? _initialBookUnread;
  bool _settledLeave = false;

  /// 本次阅读的时长/页数统计（HIS-01）。
  final ReadingSessionTracker _session = ReadingSessionTracker();

  /// 会话落库用；在 `initState` 里取好，`dispose` 里不能再碰 `ref`。
  late ReadingSessionRecorder _recorder;

  void _noteBookAndLayout(Book? book, ReaderLayout layout) {
    _lastLayout = layout;
    if (book != null) {
      _lastBook = book;
      _initialBookUnread ??= book.isUnread;
      _progressSync.noteBook(book);
    }
  }

  /// 计算切后台或退出阅读器时应当补写的页码（不需要补写时返回 null）。
  int? _exitProgressPage() {
    final pending = _progress.pendingPage;
    if (pending != null) return pending;
    if (_page > 0) return _page;
    final layout = _lastLayout;
    if ((_initialBookUnread ?? false) && layout != null && layout.total > 0) {
      return layout.page;
    }
    return null;
  }

  /// 横屏自动双页用；由 `_buildPages` 每次布局时更新（UI-P3-3）。
  bool _landscape = false;

  /// 是否平板（PLT-02）：只有平板才应用「平板默认排版」。
  bool _tablet = false;

  /// 手动修正双页分组的起点（0 基；null = 自动）。
  ///
  /// 从偏好里按**书**读（RDR-06）：以前是会话内字段，退出阅读器就丢了。
  /// 用 `read` 而不是 `watch`：这个 getter 也会在事件回调 / 进度回写里被调用，
  /// 那里不能 watch；重建由 `ReaderScreen.build` 对同一个 provider 的 watch 负责。
  int? get _spreadFrom => ref
      .read(readerPrefsProvider)
      .spreadFromFor(
        widget.bookId,
        serverKey: _resolvedSourceKey ?? ref.read(activeServerKeyProvider),
      );

  /// 最近一次 build 解析出的**有效**阅读方向。
  ///
  /// 显式传入优先；没传（搜索、阅读列表、深链）就按书的系列查。
  /// 事件回调（音量键、键盘、生命周期）用这个缓存值，不在 build 之外 watch。
  ReadingDirection _direction = ReadingDirection.unknown;

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

  /// 音量上 = 上一页，音量下 = 下一页（阅读顺序，不跟着 RTL 反转）。
  /// 纵向模式忽略：滚动交给 ListView；页数据没到时也没有 total 可用。
  void _onVolumeKey(PageTurnKey key) {
    final pages = ref.read(readerPagesProvider(_bookQuery)).value;
    if (pages == null || pages.isEmpty) return;
    final mode = _modeFor(ref.read(readerPrefsProvider));
    _requestTurn(key == PageTurnKey.next ? 1 : -1, mode);
  }

  /// 当前书的系列 id（按系列记忆设置与退出联动刷新用，UI-P3-2）。
  String? get _seriesId =>
      (_lastBook ??
              widget.book ??
              (!_settledLeave && mounted
                  ? ref.read(readerBookProvider(_bookQuery)).value
                  : null))
          ?.seriesId;

  /// 系列覆盖优先，其余用全局。
  ReaderConfig _effectiveConfig(ReaderPrefs prefs) => prefs.forSeries(
    _seriesId,
    serverKey: _resolvedSourceKey ?? ref.read(activeServerKeyProvider),
  );

  /// 外部翻页（底栏箭头 / 音量键）统一入口：交给绘制层播动画，动画结束后
  /// 它再回调 `onTurn` 真正换页；绘制层还没建好时（页数据未到）什么也不做。
  void _requestTurn(int delta, ReadingMode mode) {
    if (mode == ReadingMode.verticalScroll) return;
    _pagedKey.currentState?.turn(delta);
  }

  /// 切后台/锁屏时立刻落一次进度：只靠防抖会丢掉"看完就退出"的那一页。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台：继续计时（暂停区间会被剪掉，HIS-01）。
      _session.resume();
      return;
    }
    // 切后台：先把已读时长钉住，避免后台挂着继续算。
    _session.pause();
    if (_incognito) return;
    final page = _exitProgressPage();
    if (page != null) unawaited(_progress.flush(page));
  }

  ReadingMode _modeFor(ReaderPrefs prefs, {bool? landscape}) =>
      resolveReaderMode(
        mode: _effectiveConfig(prefs).mode,
        tabletLayout: prefs.tabletLayout,
        direction: _direction,
        landscape: landscape ?? _landscape,
        tablet: _tablet,
      );

  /// 解析本次阅读的方向：显式传入优先，否则跟随系列。
  ///
  /// 只有系列详情页知道方向；搜索、阅读列表、"下一本"、深链都只带一本书。
  /// 之前这些入口一律按 unknown 处理，RTL 书会反着翻（点击区/箭头/卷页全反）。
  /// 系列查不到（离线/深链脏数据）时回 unknown，界面按从左到右兜底，不阻塞打开。
  ReadingDirection _resolveDirection() {
    if (widget.direction != ReadingDirection.unknown) return widget.direction;
    final book = widget.book ?? ref.watch(readerBookProvider(_bookQuery)).value;
    final seriesId = book?.seriesId;
    if (seriesId == null) return ReadingDirection.unknown;
    return ref
            .watch(
              seriesDetailProvider((
                sourceKey: _resolvedSourceKey,
                seriesId: seriesId,
              )),
            )
            .value
            ?.readingDirection ??
        ReadingDirection.unknown;
  }

  /// 用当前状态构造这一屏的 [ReaderLayout]。
  ReaderLayout _buildLayout(
    List<PageInfo> pages,
    TabletLayoutChoice tabletLayout,
    ReaderConfig config,
  ) {
    final mode = resolveReaderMode(
      mode: config.mode,
      tabletLayout: tabletLayout,
      direction: _direction,
      landscape: _landscape,
      tablet: _tablet,
    );
    return ReaderLayout(
      pages: pages,
      mode: mode,
      page: _resolvePage(pages.length),
      groupFrom: _spreadFrom,
      splitWidePages: config.splitWidePages.isActive(
        mode: mode,
        landscape: _landscape,
      ),
      rightToLeft: config.direction.resolveRightToLeft(_direction),
      currentHalf: _pageHalf,
      mergedWidePageIndex: _mergedWidePageIndex,
    );
  }

  /// 用当前状态现算一份布局；页数据还没到时为 null。
  ReaderLayout? _currentLayout() {
    final pages = ref.read(readerPagesProvider(_bookQuery)).value;
    if (pages == null || pages.isEmpty) return null;
    final prefs = ref.read(readerPrefsProvider);
    return _buildLayout(pages, prefs.tabletLayout, _effectiveConfig(prefs));
  }

  int _resolvePage(int total) {
    if (total <= 0) return 1;
    if (_page > 0) return _page.clamp(1, total);
    final resumed =
        (widget.book ?? ref.read(readerBookProvider(_bookQuery)).value)
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

  void _setPage(int page, int total, {PageHalf? half}) {
    if (page == _page && half == _pageHalf) return;
    setState(() {
      if (page != _page && _mergedWidePageIndex != page - 1) {
        _mergedWidePageIndex = null;
      }
      _page = page;
      _pageHalf = half;
    });
    // 阅读会话记下"读到哪"（HIS-01）。
    _session.note(page: page);
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
      extra: ReaderArgs(
        book: next,
        direction: _direction,
        sourceKey: _resolvedSourceKey ?? next.sourceKey,
      ),
    );
  }

  /// 跳到某页（设置面板 / 缩略图）：单页/双页直接换页，纵向模式额外发一次滚动跳转。
  void _jumpToPage(int page, int total) {
    final target = page.clamp(1, total);
    setState(() {
      _page = target;
      _pageHalf = null;
      _mergedWidePageIndex = null;
      _jumpPage = target;
      _jumpToken++;
    });
    _scheduleProgress(target);
  }

  /// 只在完成态查"下一本"：没读完时多一次列表请求纯属浪费。
  Book? _nextBookFor(ReaderLayout layout, Book? book) {
    if (!layout.completed || book == null) return null;
    return ref
        .watch(
          nextBookProvider((
            sourceKey: _resolvedSourceKey,
            seriesId: book.seriesId,
            bookId: book.id,
          )),
        )
        .value;
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  void _scheduleProgress(int page) {
    if (_incognito) return;
    _progress.schedule(page);
  }
}
