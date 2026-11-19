part of 'reader_screen.dart';

/// 阅读器的状态与命令（QUA-01）。
///
/// 为什么用 part + mixin 而不是再拆一个 widget：这些方法要直接读写页码、
/// 分屏起点、隐身开关等私有状态，拆出去只会变成一长串回调参数。part 与宿主
/// 同属一个 library，私有成员照常可见，宿主文件也回到 350 行以内。
mixin _ReaderDerive on ConsumerState<ReaderScreen>, WidgetsBindingObserver {
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

  /// 本次阅读的时长/页数统计（HIS-01）。
  final ReadingSessionTracker _session = ReadingSessionTracker();

  /// 会话落库用；在 `initState` 里取好，`dispose` 里不能再碰 `ref`。
  late ReadingSessionRecorder _recorder;

  /// chrome 里"本次阅读时长"用（HIS-04）。30 秒一跳，且**只在分钟数变了**
  /// 才 setState——每秒重建整页会把长条漫画的滚动拖垮。
  Timer? _sessionTicker;
  int _shownSessionMinutes = 0;

  void startSessionTicker() {
    _sessionTicker?.cancel();
    _sessionTicker = Timer.periodic(
      const Duration(seconds: 30),
      (Timer _) => _tickSession(),
    );
  }

  void stopSessionTicker() {
    _sessionTicker?.cancel();
    _sessionTicker = null;
  }

  void _tickSession() {
    if (!mounted) return;
    if (!ref.read(readerPrefsProvider).showSessionTime) return;
    final minutes = _session.elapsed.inMinutes;
    if (minutes == _shownSessionMinutes) return;
    setState(() => _shownSessionMinutes = minutes);
  }

  /// 页码文案后面挂上"本次 12 分"（可关）。
  ///
  /// 和写进历史的那条会话同一口径（都来自 [ReadingSessionTracker]），
  /// 不会出现"阅读器里显示 12 分、历史里写着 9 分"。
  String _pageLabelWithSession(String label, AppLocalizations l10n) {
    if (!ref.watch(readerPrefsProvider).showSessionTime) return label;
    if (_shownSessionMinutes <= 0) return label;
    return l10n.readerPageLabelWithSession(label, _shownSessionMinutes);
  }

  /// 结算本次会话并写库；太短（<10s）直接丢掉。
  ///
  /// 隐身模式下不记：用户开隐身就是想"这次阅读别留痕"。
  void _settleSession({required bool completed}) {
    if (_incognito) {
      _session.finish(
        bookId: widget.bookId,
        seriesId: widget.book?.seriesId ?? widget.bookId,
        bookName: widget.book?.name ?? widget.bookId,
        completed: completed,
      );
      return;
    }
    final draft = _session.finish(
      bookId: widget.bookId,
      seriesId: widget.book?.seriesId ?? widget.bookId,
      bookName: widget.book?.name ?? widget.bookId,
      completed: completed,
      page: _page > 0 ? _page : null,
    );
    if (draft == null) return;
    unawaited(_recorder.record(draft));
  }

  /// 横屏自动双页用；由 `_buildPages` 每次布局时更新（UI-P3-3）。
  bool _landscape = false;

  /// 手动修正双页分组的起点（0 基；null = 自动）。
  ///
  /// 从偏好里按**书**读（RDR-06）：以前是会话内字段，退出阅读器就丢了。
  /// 用 `read` 而不是 `watch`：这个 getter 也会在事件回调 / 进度回写里被调用，
  /// 那里不能 watch；重建由 `ReaderScreen.build` 对同一个 provider 的 watch 负责。
  int? get _spreadFrom =>
      ref.read(readerPrefsProvider).spreadFrom[widget.bookId];

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
    if (state == AppLifecycleState.resumed) {
      // 回到前台：继续计时（暂停区间会被剪掉，HIS-01）。
      _session.resume();
      return;
    }
    // 切后台：先把已读时长钉住，避免后台挂着继续算。
    _session.pause();
    final total =
        ref.read(readerPagesProvider(widget.bookId)).value?.length ?? 0;
    if (total == 0) return;
    if (_incognito) return;
    unawaited(_progress.flush(_resolvePage(total)));
  }

  ReadingMode _modeFor(ReaderPrefs prefs, {bool? landscape}) =>
      prefs.mode.resolve(_direction, landscape: landscape ?? _landscape);

  /// 解析本次阅读的方向：显式传入优先，否则跟随系列。
  ///
  /// 只有系列详情页知道方向；搜索、阅读列表、"下一本"、深链都只带一本书。
  /// 之前这些入口一律按 unknown 处理，RTL 书会反着翻（点击区/箭头/卷页全反）。
  /// 系列查不到（离线/深链脏数据）时回 unknown，界面按从左到右兜底，不阻塞打开。
  ReadingDirection _resolveDirection() {
    if (widget.direction != ReadingDirection.unknown) return widget.direction;
    final book =
        widget.book ?? ref.watch(readerBookProvider(widget.bookId)).value;
    final seriesId = book?.seriesId;
    if (seriesId == null) return ReadingDirection.unknown;
    return ref.watch(seriesDetailProvider(seriesId)).value?.readingDirection ??
        ReadingDirection.unknown;
  }

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
      extra: ReaderArgs(book: next, direction: _direction),
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
    // 落盘而不是只改会话状态：退出重进还要保持分组（RDR-06）。
    ref.read(readerPrefsProvider.notifier).setSpreadFrom(widget.bookId, next);
    if (next != null) {
      // 跳到手动分组的起点，并照常回写进度。
      _page = page.clamp(1, total);
      _scheduleProgress(_page);
    }
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
    final rightToLeft = prefs.direction.resolveRightToLeft(_direction);
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
