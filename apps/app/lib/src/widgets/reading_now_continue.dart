import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/widgets/book_hero_tag.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:komga_native/src/widgets/reading_now_states.dart';
import 'package:material_ui/material_ui.dart';

export 'package:komga_native/src/widgets/reading_now_states.dart';

/// "正在读"页顶部的继续阅读卡片，以及它的加载/空/失败三态（FIX-05 / ARC-12）。
class ReadingNowContinue extends StatefulWidget {
  const ReadingNowContinue({
    required this.books,
    required this.hasError,
    required this.onRetry,
    super.key,
  });

  final List<Book>? books;
  final bool hasError;
  final Future<void> Function() onRetry;

  @override
  State<ReadingNowContinue> createState() => _ReadingNowContinueState();
}

class _ReadingNowContinueState extends State<ReadingNowContinue> {
  List<Book>? _lastGood;

  @override
  Widget build(BuildContext context) {
    final fresh = widget.books;
    if (fresh != null) _lastGood = fresh;
    final items = fresh ?? _lastGood;
    if (items != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (items.isEmpty)
            const EmptyContinueCard()
          else
            ContinueCard(book: items.first),
          if (widget.hasError)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: RefreshFailureHint(onRetry: widget.onRetry),
            ),
        ],
      );
    }
    if (widget.hasError) {
      return ContinueFailure(onRetry: widget.onRetry);
    }
    return const ContinueSkeleton();
  }
}

/// 继续阅读的大卡片：封面 + 书名 + 进度 + 主按钮。
class ContinueCard extends ConsumerWidget {
  const ContinueCard({required this.book, super.key});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final Uint8List? bytes = ref.watch(bookCoverProvider(book.id)).value;
    final direction =
        ref
            .watch(seriesDetailProvider(book.seriesId))
            .value
            ?.readingDirection ??
        ReadingDirection.unknown;
    final progress = book.readProgress;
    final seriesTitle = book.seriesTitle;
    final headline = seriesTitle ?? book.name;
    final progressLabel = progress == null
        ? l10n.bookPages(book.pagesCount)
        : l10n.bookPageProgress(progress.page, book.pagesCount);
    final detail = seriesTitle == null
        ? progressLabel
        : '${book.name} · $progressLabel';
    final shape = AppShapes.of(context, AppShapes.panel);
    final heroTag =
        AppTheme.isEink(theme) ||
            (MediaQuery.maybeDisableAnimationsOf(context) ?? false)
        ? null
        : bookHeroTag(book.id);
    final cover = ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: SizedBox(
        width: AppSizes.shelfCover.width,
        height: AppSizes.shelfCover.height,
        child: bytes == null
            ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
            : CoverImage(bytes: bytes),
      ),
    );

    return Semantics(
      key: const Key('reading-now-continue'),
      container: true,
      button: true,
      label: '$headline, $detail',
      onTap: () => unawaited(_open(context, book, direction, heroTag)),
      child: ExcludeSemantics(
        child: PressableScale(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_open(context, book, direction, heroTag)),
            child: GlassSurface(
              shape: shape,
              shadows: AppShadows.card,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    heroTag == null ? cover : Hero(tag: heroTag, child: cover),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            l10n.pickUpWhereYouLeftOff,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            headline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.of(context).headline,
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          GlassPillButton(
                            icon: Icons.play_arrow,
                            label: l10n.continueReading,
                            onPressed: () => unawaited(
                              _open(context, book, direction, heroTag),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    Book book,
    ReadingDirection direction,
    String? heroTag,
  ) async {
    await context.push(
      '/reader/${book.id}',
      extra: ReaderArgs(book: book, direction: direction, heroTag: heroTag),
    );
  }
}
