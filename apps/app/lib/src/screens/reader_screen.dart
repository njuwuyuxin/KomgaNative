import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/providers/series_read_provider.dart';
import 'package:yomu/src/providers/settings_provider.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/widgets/edge_swipe_back.dart';
import 'package:yomu/src/widgets/reader_content_viewport.dart';
import 'package:yomu/src/widgets/reader_layout.dart';
import 'package:yomu/src/widgets/reader_navigation_state.dart';
import 'package:yomu/src/widgets/reader_opening_hero.dart';
import 'package:yomu/src/widgets/reader_page_exporter.dart';
import 'package:yomu/src/widgets/reader_paged_view.dart';
import 'package:yomu/src/widgets/reader_pages_gate.dart';
import 'package:yomu/src/widgets/reader_palette.dart';
import 'package:yomu/src/widgets/reader_preloader.dart';
import 'package:yomu/src/widgets/reader_session_coordinator.dart';
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

  String? get _sourceKey => _session.resolvedSourceKey;
  ReaderBookQuery get _bookQuery =>
      (sourceKey: _sourceKey, bookId: widget.bookId);
  String get _serverKey => _sourceKey ?? ref.read(activeServerKeyProvider);

  String? get _seriesId =>
      (_session.lastBook ??
              widget.book ??
              (!_session.settledLeave && mounted
                  ? ref.read(readerBookProvider(_bookQuery)).value
                  : null))
          ?.seriesId;

  ReaderConfig _effectiveConfig(ReaderPrefs prefs) =>
      prefs.forSeries(_seriesId, serverKey: _serverKey);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = ReaderSessionCoordinator(
      bookId: widget.bookId,
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
    final initialKey = widget.sourceKey;
    if (initialKey != null && initialKey.isNotEmpty) {
      _session.resolvedSourceKey = initialKey;
    } else if (widget.book?.isCloud ?? false) {
      _session.resolvedSourceKey = widget.book!.sourceKey;
    }
    _session.start(initialPage: widget.book?.readProgress?.page ?? 1);
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
    final book = widget.book ?? ref.watch(readerBookProvider(bookQuery)).value;
    _nav.direction = _resolveDirection(book);
    final allPrefs = ref.watch(readerPrefsProvider);
    final config = allPrefs.forSeries(
      book?.seriesId ?? _seriesId,
      serverKey: _sourceKey ?? ref.watch(activeServerKeyProvider),
    );
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
    return _sourceKey == null
        ? body
        : ScopedSourceScope(sourceKey: _sourceKey, child: body);
  }

  Widget _buildPages(
    BuildContext context,
    bool isEink,
    List<PageInfo> pages,
    TabletLayoutChoice tabletLayout,
    ReaderConfig config,
    Book? book,
  ) {
    _nav.landscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    _nav.tablet =
        WindowSizeClass.of(MediaQuery.sizeOf(context).width) ==
        WindowSizeClass.expanded;
    final layout = _buildLayout(pages, tabletLayout, config);
    _session.noteBookAndLayout(book, layout);
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
    ReaderConfig config,
  ) => _nav.buildLayout(
    pages: pages,
    tabletLayout: tabletLayout,
    config: config,
    resumedPage: (widget.book ?? ref.read(readerBookProvider(_bookQuery)).value)
        ?.readProgress
        ?.page,
    groupFrom: ref
        .read(readerPrefsProvider)
        .spreadFromFor(widget.bookId, serverKey: _serverKey),
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
