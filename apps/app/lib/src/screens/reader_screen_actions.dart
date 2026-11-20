part of 'reader_screen.dart';

/// 阅读器的分享、隐身、双页分组与物理按键命令混入（ARC-12）。
mixin _ReaderActions on ConsumerState<ReaderScreen>, _ReaderDerive {
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
    } on PlatformException {
      if (mounted) {
        _showShareError(AppLocalizations.of(context).sharePageFailed);
      }
    }
  }

  void _showShareError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
