part of 'reader_screen.dart';

/// 阅读器的会话计时、退出进度结算、保存/分享、隐身、双页分组与物理按键命令混入（ARC-12）。
mixin _ReaderActions on ConsumerState<ReaderScreen>, _ReaderDerive {
  /// chrome 里"本次阅读时长"用（HIS-04）。30 秒一跳，只在分钟数变了才 setState。
  Timer? _sessionTicker;
  int _shownSessionMinutes = 0;
  bool _savingImage = false;

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
    if (!_effectiveConfig(ref.read(readerPrefsProvider)).showSessionTime) {
      return;
    }
    final minutes = _session.elapsed.inMinutes;
    if (minutes == _shownSessionMinutes) return;
    setState(() => _shownSessionMinutes = minutes);
  }

  String _pageLabelWithSession(
    String label,
    AppLocalizations l10n, {
    required bool showSessionTime,
  }) {
    if (!showSessionTime || _shownSessionMinutes <= 0) return label;
    return l10n.readerPageLabelWithSession(label, _shownSessionMinutes);
  }

  void _settleSession({required bool completed}) {
    final book = _lastBook ?? widget.book;
    if (_incognito) {
      _session.finish(
        bookId: widget.bookId,
        seriesId: book?.seriesId ?? widget.bookId,
        bookName: book?.name ?? widget.bookId,
        completed: completed,
      );
      return;
    }
    final draft = _session.finish(
      bookId: widget.bookId,
      seriesId: book?.seriesId ?? widget.bookId,
      bookName: book?.name ?? widget.bookId,
      completed: completed,
      page: _page > 0 ? _page : null,
    );
    if (draft == null) return;
    unawaited(
      _recorder.record(draft, scope: _bookScope.isEmpty ? null : _bookScope),
    );
  }

  /// 退出阅读器或切换下一本书时幂等落盘进度并通知书架/"正在读"联动刷新。
  void _settleProgressOnLeave() {
    if (_settledLeave) return;
    _settledLeave = true;
    final seriesId = _seriesId;
    final exitPage = _exitProgressPage();
    final isCompleted =
        !_incognito &&
        exitPage != null &&
        (_lastLayout?.isCompletedAt(exitPage) ?? false);
    final completedBook = isCompleted ? (_lastBook ?? widget.book) : null;
    unawaited(
      _committer.settle(
        flushProgress: _flushProgressForLeave,
        bookId: widget.bookId,
        seriesId: seriesId,
        sourceKey: _resolvedSourceKey,
        completedBook: completedBook,
      ),
    );
  }

  Future<bool> _flushProgressForLeave() async {
    if (_incognito) {
      _progress.cancel();
      return _progress.hasWritten;
    }
    final targetPage = _exitProgressPage();
    if (targetPage != null) {
      await _progress.flush(targetPage);
    }
    return _progress.hasWritten;
  }

  Future<void> _saveScreenImage(ReaderLayout layout, bool rightToLeft) async {
    if (_savingImage || layout.total <= 0) return;
    _savingImage = true;
    try {
      final orderedPages = resolveSavePages(
        mode: layout.mode,
        currentPage: layout.page,
        spread: layout.spread,
        rightToLeft: rightToLeft,
      );
      final repo = ref.read(
        readerRepositoryForSourceProvider(_resolvedSourceKey),
      );
      final prepared = await prepareScreenImageForSave(
        bookId: widget.bookId,
        orderedPages: orderedPages,
        loadPage: (int p) => repo.pageImage(widget.bookId, p),
      );
      final result = await ref
          .read(imageSaverProvider)
          .saveImage(
            prepared.bytes,
            fileName: prepared.fileName,
            mimeType: prepared.mimeType,
          );
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      switch (result) {
        case ImageSaveSuccess():
          unawaited(AppHaptics.selection());
          _showReaderToast(l10n.savePageImageSuccess);
        case ImageSaveFailure(kind: ImageSaveFailureKind.permissionDenied):
          _showReaderToast(l10n.savePageImagePermissionDenied);
        case ImageSaveFailure(
          kind: ImageSaveFailureKind.unsupported ||
              ImageSaveFailureKind.ioError,
        ):
          _showReaderToast(l10n.savePageImageFailed);
      }
    } on ShelfFailure catch (failure) {
      if (mounted) {
        _showReaderToast(
          AppLocalizations.of(context).failureTitle(failure.kind),
        );
      }
    } on FormatException {
      if (mounted) {
        _showReaderToast(AppLocalizations.of(context).savePageImageFailed);
      }
    } finally {
      _savingImage = false;
    }
  }

  Future<void> _sharePage(int page) async {
    final handler = widget.onSharePage;
    if (handler != null) {
      await handler(page);
      return;
    }
    try {
      final bytes = await ref
          .read(readerRepositoryForSourceProvider(_resolvedSourceKey))
          .pageImage(widget.bookId, page);
      await sharePageImage(
        bytes,
        fileName: 'yomu-${widget.bookId}-page-$page.png',
      );
    } on ShelfFailure catch (failure) {
      if (mounted) {
        _showReaderToast(
          AppLocalizations.of(context).failureTitle(failure.kind),
        );
      }
    } on PlatformException {
      if (mounted) {
        _showReaderToast(AppLocalizations.of(context).sharePageFailed);
      }
    }
  }

  void _showReaderToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleIncognito() {
    setState(() => _incognito = !_incognito);
    if (_incognito) _progress.cancel();
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
    ref.read(readerPrefsProvider.notifier).setSpreadFrom(widget.bookId, next);
    if (next != null) {
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

  Widget _buildReaderContent(
    BuildContext context, {
    required bool isEink,
    required List<PageInfo> pages,
    required ReaderConfig config,
    required ReaderLayout layout,
    required ReaderPalette palette,
    required bool rightToLeft,
    required Book? nextBook,
  }) {
    final mode = layout.mode;
    final total = pages.length;
    if (mode == ReadingMode.verticalScroll) {
      return ReaderVerticalView(
        bookId: widget.bookId,
        pages: pages,
        initialPage: layout.page,
        jumpToken: _jumpToken,
        jumpPage: _jumpPage,
        palette: palette,
        trimBorders: config.trimBorders,
        autoScrollSpeed: config.autoScrollSpeed,
        autoScrollAllowed: !isEink,
        onPageChanged: (int p) => _setPage(p, total),
        onToggleChrome: _toggleChrome,
      );
    }
    return ReaderPagedView(
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
    );
  }

  void _toggleTempMerge(int pageIndex) {
    setState(() {
      _mergedWidePageIndex = _mergedWidePageIndex == pageIndex
          ? null
          : pageIndex;
      _pageHalf = null;
    });
  }

  void _handlePagedTurn(
    ReaderLayout layout,
    int delta,
    int total,
    Book? nextBook,
  ) {
    if (layout.isWideSplitActive) {
      final splitTarget = layout.turnSplitTarget(delta);
      if (splitTarget != null) {
        _setPage(splitTarget.pageNumber, total, half: splitTarget.half);
        return;
      }
      if (delta > 0 && nextBook != null) _openNext(nextBook);
      return;
    }
    final target = layout.turnTarget(delta);
    if (target != null) {
      _setPage(target, total);
      return;
    }
    if (delta > 0 && nextBook != null) _openNext(nextBook);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final pages = ref.read(readerPagesProvider(_bookQuery)).value;
    if (pages == null || pages.isEmpty) return KeyEventResult.ignored;
    final allPrefs = ref.read(readerPrefsProvider);
    final config = _effectiveConfig(allPrefs);
    final mode = _modeFor(allPrefs);
    final rightToLeft = config.direction.resolveRightToLeft(_direction);
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
