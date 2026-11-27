import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/features/reader/reader_layout.dart';
import 'package:yomu/src/features/reader/reader_navigation_state.dart';
import 'package:yomu/src/features/reader/reader_page_exporter.dart';
import 'package:yomu/src/features/reader/reader_preloader.dart';
import 'package:yomu/src/features/reader/reader_session_coordinator.dart';
import 'package:yomu/src/providers/active_source_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/providers/series_read_provider.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/widgets/edge_swipe_back.dart';
import 'package:yomu/src/widgets/reader_content_viewport.dart';
import 'package:yomu/src/widgets/reader_opening_hero.dart';
import 'package:yomu/src/widgets/reader_paged_view.dart';
import 'package:yomu/src/widgets/reader_pages_gate.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_stage.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu/src/widgets/volume_key_scope.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_platform/yomu_platform.dart';
import 'package:yomu_reader/yomu_reader.dart';

export 'package:yomu/src/screens/reader_args.dart';
export 'package:yomu/src/widgets/wake_lock_scope.dart';

/// 漫画阅读器：单页 / 双页跨页 / 纵向连续（P3-1 内聚职责编排）。
///
/// 职责分工：
/// - 本类只负责页面生命周期、内容源解析与协作者装配；
/// - 页码/半幅/临时合页/方向状态机在 [ReaderNavigationState]；
/// - 会话计时、防抖进度落盘、隐身与退出结算在 [ReaderSessionCoordinator]；
/// - 画面保存、系统分享、双页分组与切书在 [ReaderPageExporter]；
/// - 舞台拼装与正文绘制在 [ReaderStage] / [ReaderContentViewport]。
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    required this.bookId,
    this.book,
    this.sourceKey,
    this.direction = ReadingDirection.unknown,
    this.heroTag,
    this.onOpenNext,
    this.onSharePage,
    super.key,
  });

  final String bookId;
  final Book? book;
  final String? sourceKey;
  final ReadingDirection direction;
  final String? heroTag;
  final void Function(Book next)? onOpenNext;
  final Future<void> Function(int page)? onSharePage;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  final ReaderNavigationState _nav = ReaderNavigationState();
  final ReaderPageExporter _exporter = ReaderPageExporter();
  final GlobalKey<ReaderPagedViewState> _pagedKey = GlobalKey();
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'reader-keyboard');
  late final ReaderSessionCoordinator _session;
  late final ReaderPreloader _preloader = ReaderPreloader(
    fetch: (int page) => ref
        .read(readerRepositoryForSourceProvider(_sourceKey))
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

  String get _sourceKey => _session.resolvedSourceKey;
  ReaderBookQuery get _bookQuery =>
      (sourceKey: _sourceKey, bookId: widget.bookId);

  String? _lastKnownSeriesId;

  /// 纯内存读取当前书所属系列 ID（绝不在 `dispose()` 或退出回调里触碰 `ref.read`，P3）。
  String? get _seriesId =>
      (_session.lastBook ?? widget.book)?.seriesId ?? _lastKnownSeriesId;

  ReaderConfig _effectiveConfig(ReaderPrefs prefs) =>
      prefs.forSeries(_seriesId, serverKey: _sourceKey);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastKnownSeriesId = widget.book?.seriesId;
    _nav.direction = widget.direction;
    final initialKey = widget.sourceKey;
    final resolvedInitialSource = (initialKey != null && initialKey.isNotEmpty)
        ? initialKey
        : (widget.book?.isCloud ?? false)
        ? widget.book!.sourceKey
        : ref.read(activeSourceProvider).sourceKey;
    _session = ReaderSessionCoordinator(
      bookId: widget.bookId,
      sourceKey: resolvedInitialSource,
      initialBook: widget.book,
      progressSync: ref.read(progressSyncProvider),
      recorder: ref.read(readingSessionRecorderProvider),
      committer: ref.read(readerProgressCommitterProvider),
      resolveLiveLayout: () => mounted ? _currentLayout() : null,
      isShowSessionTimeEnabled: () =>
          mounted &&
          _effectiveConfig(ref.read(readerPrefsProvider)).showSessionTime,
      onSessionMinutesChanged: () {
        if (mounted) setState(() {});
      },
    );
    final initialBook =
        widget.book ?? ref.read(readerBookProvider(_bookQuery)).value;
    if (initialBook != null) {
      _lastKnownSeriesId = initialBook.seriesId;
      _session.noteBook(initialBook);
    }
    _session.start(initialPage: initialBook?.readProgress?.page ?? 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scoped = widget.sourceKey ?? ScopedSourceScope.maybeOf(context);
    if (scoped != null && scoped.isNotEmpty) {
      _session.resolvedSourceKey = scoped;
    }
    _nav.landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    _nav.tablet =
        WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.expanded;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.handleAppLifecycleState(state);

  @override
  void dispose() {
    _session.dispose(seriesId: _seriesId);
    WidgetsBinding.instance.removeObserver(this);
    _keyboardFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEink = ref.watch(effectiveEinkProvider);
    final bookQuery = _bookQuery;
    ref.listen<AsyncValue<Book?>>(readerBookProvider(bookQuery), (_, next) {
      final loaded = next.value;
      if (loaded != null) {
        _lastKnownSeriesId = loaded.seriesId;
        _session.noteBook(loaded);
      }
    });
    final book = widget.book ?? ref.watch(readerBookProvider(bookQuery)).value;
    final seriesId = book?.seriesId ?? _seriesId;
    final direction = _resolveDirection(book);
    // 同步解析后的阅读方向，保证已缓存的 seriesDetailProvider 与异步到达路径行为一致（N1）。
    _nav.direction = direction;
    final allPrefs = ref.watch(readerPrefsProvider);
    final config = allPrefs.forSeries(seriesId, serverKey: _sourceKey);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final body = PopScope(
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) _session.settleProgressOnLeave(seriesId: _seriesId);
      },
      child: EdgeSwipeBack(
        child: VolumeKeyScope(
          onKey: _onVolumeKey,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ReaderPagesGate(
                pages: ref.watch(readerPagesProvider(bookQuery)),
                palette: ReaderPalette.of(isEink: isEink),
                onRetry: () => ref.invalidate(readerPagesProvider(bookQuery)),
                builder: (List<PageInfo> pages) => _buildPages(
                  context,
                  isEink,
                  pages,
                  allPrefs.tabletLayout,
                  config,
                  book,
                  direction,
                ),
              ),
              if (widget.heroTag != null && !isEink && !reduceMotion)
                Positioned.fill(
                  child: ReaderOpeningHero(
                    bookId: widget.bookId,
                    page: widget.book?.readProgress?.page ?? 1,
                    tag: widget.heroTag!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return ScopedSourceScope(sourceKey: _sourceKey, child: body);
  }

  Widget _buildPages(
    BuildContext context,
    bool isEink,
    List<PageInfo> pages,
    TabletLayoutChoice tabletLayout,
    ReaderConfig config,
    Book? book,
    ReadingDirection direction,
  ) {
    final layout = _buildLayout(
      pages,
      tabletLayout,
      config,
      direction: direction,
    );
    _session.noteLayout(layout);
    _preloader.scheduleFor('${layout.page}:${layout.mode.name}', () {
      final live = _currentLayout();
      if (live == null || live.mode == ReadingMode.verticalScroll) return;
      _preloader.planAround(
        page: live.page,
        total: live.total,
        spreads: live.spreads,
      );
    });
    return ReaderStage(
      bookId: widget.bookId,
      book: book,
      sourceKey: _sourceKey,
      isEink: isEink,
      pages: pages,
      config: config,
      layout: layout,
      nav: _nav,
      session: _session,
      exporter: _exporter,
      pagedKey: _pagedKey,
      keyboardFocus: _keyboardFocus,
      onKeyEvent: _onKeyEvent,
      onMutated: () => setState(() {}),
      onRequestTurn: (int d) => _requestTurn(d, layout.mode),
      onOpenNext: widget.onOpenNext,
      onSharePage: widget.onSharePage,
    );
  }

  ReadingDirection _resolveDirection(Book? book) {
    if (widget.direction != ReadingDirection.unknown) return widget.direction;
    final seriesId = book?.seriesId;
    if (seriesId == null) return ReadingDirection.unknown;
    return ref
            .watch(
              seriesDetailProvider((sourceKey: _sourceKey, seriesId: seriesId)),
            )
            .value
            ?.readingDirection ??
        ReadingDirection.unknown;
  }

  ReaderLayout _buildLayout(
    List<PageInfo> pages,
    TabletLayoutChoice tabletLayout,
    ReaderConfig config, {
    ReadingDirection? direction,
  }) => _nav.buildLayout(
    pages: pages,
    tabletLayout: tabletLayout,
    config: config,
    resumedPage: (widget.book ?? ref.read(readerBookProvider(_bookQuery)).value)
        ?.readProgress
        ?.page,
    groupFrom: ref
        .read(readerPrefsProvider)
        .spreadFromFor(widget.bookId, serverKey: _sourceKey),
    direction: direction,
  );

  ReaderLayout? _currentLayout() {
    final pages = ref.read(readerPagesProvider(_bookQuery)).value;
    if (pages == null || pages.isEmpty) return null;
    final prefs = ref.read(readerPrefsProvider);
    return _buildLayout(pages, prefs.tabletLayout, _effectiveConfig(prefs));
  }

  void _requestTurn(int delta, ReadingMode mode) {
    if (mode != ReadingMode.verticalScroll) _pagedKey.currentState?.turn(delta);
  }

  void _onVolumeKey(PageTurnKey key) {
    final pages = ref.read(readerPagesProvider(_bookQuery)).value;
    if (pages == null || pages.isEmpty) return;
    final prefs = ref.read(readerPrefsProvider);
    _requestTurn(
      key == PageTurnKey.next ? 1 : -1,
      _nav.resolveMode(prefs: prefs, config: _effectiveConfig(prefs)),
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final pages = ref.read(readerPagesProvider(_bookQuery)).value;
    if (pages == null || pages.isEmpty) return KeyEventResult.ignored;
    final prefs = ref.read(readerPrefsProvider);
    final config = _effectiveConfig(prefs);
    final action = _nav.resolveKeyEvent(event, config);
    if (action == null) return KeyEventResult.ignored;
    switch (action) {
      case ReaderTurnAction(:final delta):
        _requestTurn(delta, _nav.resolveMode(prefs: prefs, config: config));
      case ReaderExitAction():
        unawaited(Navigator.of(context).maybePop());
    }
    return KeyEventResult.handled;
  }
}
