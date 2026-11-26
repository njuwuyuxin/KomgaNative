import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reader_prefs.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/providers/reader_prefs_provider.dart';
import 'package:yomu/src/providers/reader_providers.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';
import 'package:yomu/src/widgets/reader_background.dart';
import 'package:yomu/src/widgets/reader_bottom_chrome.dart';
import 'package:yomu/src/widgets/reader_content_viewport.dart';
import 'package:yomu/src/widgets/reader_frame.dart';
import 'package:yomu/src/widgets/reader_layout.dart';
import 'package:yomu/src/widgets/reader_navigation_state.dart';
import 'package:yomu/src/widgets/reader_page_exporter.dart';
import 'package:yomu/src/widgets/reader_paged_view.dart';
import 'package:yomu/src/widgets/reader_session_coordinator.dart';
import 'package:yomu/src/widgets/reader_system_ui.dart';
import 'package:yomu/src/widgets/reader_top_bar.dart';
import 'package:yomu/src/widgets/wake_lock_scope.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu_reader/yomu_reader.dart';

/// 阅读器主舞台：组合顶栏、正文视口、底栏以及保存/分享/双页分组/切书等用户动作（P3-1）。
class ReaderStage extends ConsumerWidget {
  const ReaderStage({
    required this.bookId,
    required this.book,
    required this.sourceKey,
    required this.isEink,
    required this.pages,
    required this.config,
    required this.layout,
    required this.nav,
    required this.session,
    required this.exporter,
    required this.pagedKey,
    required this.keyboardFocus,
    required this.onKeyEvent,
    required this.onMutated,
    required this.onRequestTurn,
    this.onOpenNext,
    this.onSharePage,
    super.key,
  });

  final String bookId;
  final Book? book;
  final String? sourceKey;
  final bool isEink;
  final List<PageInfo> pages;
  final ReaderConfig config;
  final ReaderLayout layout;
  final ReaderNavigationState nav;
  final ReaderSessionCoordinator session;
  final ReaderPageExporter exporter;
  final GlobalKey<ReaderPagedViewState> pagedKey;
  final FocusNode keyboardFocus;
  final FocusOnKeyEventCallback onKeyEvent;
  final VoidCallback onMutated;
  final ValueChanged<int> onRequestTurn;
  final void Function(Book next)? onOpenNext;
  final Future<void> Function(int page)? onSharePage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = layout.mode;
    final page = layout.page;
    final total = pages.length;
    final rightToLeft = config.direction.resolveRightToLeft(nav.direction);
    final palette = resolveReaderPalette(
      isEink: isEink,
      config: config,
      layout: layout,
      ref: ref,
      bookId: bookId,
      sourceKey: sourceKey,
    );
    final nextBook = layout.completed && book != null
        ? ref
              .watch(
                nextBookProvider((
                  sourceKey: sourceKey,
                  seriesId: book!.seriesId,
                  bookId: book!.id,
                )),
              )
              .value
        : null;
    final mins = session.shownSessionMinutes;
    final pageLabel = (config.showSessionTime && mins > 0)
        ? l10n.readerPageLabelWithSession(layout.pageLabel(l10n), mins)
        : layout.pageLabel(l10n);

    void openNext(Book next) => exporter.openNextBook(
      context,
      next: next,
      direction: nav.direction,
      sourceKey: sourceKey,
      overrideHandler: onOpenNext,
    );

    void jumpToPage(int targetPage) {
      final target = nav.jumpTo(targetPage, total);
      onMutated();
      session.scheduleProgress(target);
    }

    void groupFromPage(int targetPage) {
      final serverKey = sourceKey ?? ref.read(activeServerKeyProvider);
      final result = exporter.toggleGroupFrom(
        bookId: bookId,
        page: targetPage,
        total: total,
        serverKey: serverKey,
        currentSpreadFrom: ref
            .read(readerPrefsProvider)
            .spreadFromFor(bookId, serverKey: serverKey),
        prefsController: ref.read(readerPrefsProvider.notifier),
        l10n: AppLocalizations.of(context),
      );
      if (result.groupedPage != null) {
        nav.setPage(result.groupedPage!);
        session.scheduleProgress(result.groupedPage!);
      }
      exporter.showToast(context, result.toast);
    }

    Future<void> sharePage(int targetPage) async {
      final error = await exporter.sharePage(
        bookId: bookId,
        page: targetPage,
        repository: ref.read(readerRepositoryForSourceProvider(sourceKey)),
        l10n: () => AppLocalizations.of(context),
        overrideHandler: onSharePage,
      );
      if (error != null && context.mounted) {
        exporter.showToast(context, error);
      }
    }

    Future<void> saveScreenImage() async {
      final message = await exporter.saveScreenImage(
        bookId: bookId,
        layout: layout,
        rightToLeft: rightToLeft,
        repository: ref.read(readerRepositoryForSourceProvider(sourceKey)),
        imageSaver: ref.read(imageSaverProvider),
        l10n: () => AppLocalizations.of(context),
      );
      if (message != null && context.mounted) {
        exporter.showToast(context, message);
      }
    }

    return Focus(
      focusNode: keyboardFocus,
      autofocus: true,
      onKeyEvent: onKeyEvent,
      child: WakeLockScope(
        enabled: config.keepAwake,
        child: ReaderSystemUi(
          immersive: !nav.chromeVisible,
          child: ReaderFrame(
            palette: palette,
            chromeVisible: nav.chromeVisible,
            dimOpacity: config.dimOpacity,
            floatingAction: layout.canToggleTempMerge
                ? ReaderTempMergePill(
                    merged: layout.isTempMerged,
                    label: layout.isTempMerged
                        ? l10n.readerTempSplitSpread
                        : l10n.readerTempMergeSpread,
                    palette: palette,
                    onPressed: () {
                      nav.toggleTempMerge(page - 1);
                      onMutated();
                    },
                  )
                : null,
            topBar: ReaderTopBar(
              bookId: bookId,
              seriesId: book?.seriesId,
              title: book?.name ?? l10n.readerBookFallback,
              pageLabel: pageLabel,
              palette: palette,
              mode: mode,
              page: page,
              total: total,
              direction: nav.direction,
              onJump: jumpToPage,
              onGroupFrom: mode == ReadingMode.doublePage
                  ? groupFromPage
                  : null,
              incognito: session.incognito,
              onToggleIncognito: () {
                final enabled = session.toggleIncognito();
                onMutated();
                exporter.showToast(
                  context,
                  enabled ? l10n.incognitoEnabled : l10n.incognitoDisabled,
                );
              },
              onSavePage: () => unawaited(saveScreenImage()),
              onSharePage: () => unawaited(sharePage(page)),
            ),
            content: ReaderContentViewport(
              bookId: bookId,
              isEink: isEink,
              pages: pages,
              config: config,
              layout: layout,
              palette: palette,
              rightToLeft: rightToLeft,
              jumpToken: nav.jumpToken,
              jumpPage: nav.jumpPage,
              pagedKey: pagedKey,
              onVerticalPageChanged: (int p) {
                if (!nav.setPage(p)) return;
                onMutated();
                session.notePageChanged(p);
              },
              onPagedTurn: (int delta) {
                switch (nav.handlePagedTurn(
                  layout: layout,
                  delta: delta,
                  hasNextBook: nextBook != null,
                )) {
                  case ReaderTurnNone():
                    return;
                  case ReaderTurnMoved(:final page):
                    onMutated();
                    session.notePageChanged(page);
                  case ReaderTurnOpenNextBook():
                    if (nextBook != null) openNext(nextBook);
                }
              },
              onToggleChrome: () {
                nav.toggleChrome();
                onMutated();
              },
            ),
            bottomBar: ReaderBottomChrome(
              bookId: bookId,
              layout: layout,
              palette: palette,
              rightToLeft: rightToLeft,
              nextBook: nextBook,
              onJump: jumpToPage,
              onGroupFrom: mode == ReadingMode.doublePage
                  ? groupFromPage
                  : null,
              onSharePage: sharePage,
              onOpenNext: nextBook == null ? null : () => openNext(nextBook),
              onBack: () => context.pop(),
              onPrevious: layout.canGoBack ? () => onRequestTurn(-1) : null,
              onNext: layout.canGoForward ? () => onRequestTurn(1) : null,
            ),
          ),
        ),
      ),
    );
  }
}
