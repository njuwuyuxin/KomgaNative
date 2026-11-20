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
    unawaited(_recorder.record(draft));
  }

  /// 退出阅读器或切换下一本书时幂等落盘进度并通知书架/"正在读"联动刷新。
  void _settleProgressOnLeave() {
    if (_settledLeave) return;
    _settledLeave = true;
    final seriesId = _seriesId;
    unawaited(
      _committer.settle(
        flushProgress: _flushProgressForLeave,
        bookId: widget.bookId,
        seriesId: seriesId,
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
      final repo = ref.read(readerRepositoryProvider);
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
      _showReaderToast(failure.message);
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
          .read(readerRepositoryProvider)
          .pageImage(widget.bookId, page);
      await sharePageImage(
        bytes,
        fileName: 'komganative-${widget.bookId}-page-$page.png',
      );
    } on ShelfFailure catch (failure) {
      _showReaderToast(failure.message);
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

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final pages = ref.read(readerPagesProvider(widget.bookId)).value;
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
