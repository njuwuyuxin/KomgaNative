import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/book_selection.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/series_header_cover.dart';
import 'package:komga_native/src/widgets/series_header_details.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情页的头部（UI-P2-4 / ARC-12 拆出标题块与简介组件）。
class SeriesHeader extends ConsumerWidget {
  const SeriesHeader({
    required this.series,
    required this.seriesId,
    required this.heroTag,
    required this.books,
    required this.metadataLoading,
    required this.booksLoading,
    required this.onOpenBook,
    this.topPadding = 0,
    super.key,
  });

  final Series? series;
  final String seriesId;
  final String heroTag;
  final List<Book>? books;
  final bool metadataLoading;
  final bool booksLoading;
  final void Function(Book book) onOpenBook;

  /// 为悬浮顶栏与状态栏让出的上方留白；背景模糊色会贯通铺满这一段直达屏幕顶端。
  final double topPadding;

  static const int summaryMaxLines = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isEink = AppTheme.isEink(theme);
    final cover = ref.watch(seriesCoverProvider(seriesId));
    final Uint8List? bytes = switch (cover) {
      AsyncData<Uint8List?>(:final value) => value,
      _ => null,
    };
    final books = this.books;
    final next = books == null ? null : nextBookToRead(books);
    final unstarted = books == null || isUnstartedSeries(books);
    final summary = series?.summary?.trim() ?? '';

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        topPadding + AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SeriesHeaderCover(bytes: bytes, heroTag: heroTag),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: metadataLoading
                    ? const Shimmer(
                        child: ExcludeSemantics(
                          child: SeriesTitleSkeleton(
                            key: Key('series-title-skeleton'),
                          ),
                        ),
                      )
                    : SeriesTitleBlock(series: series),
              ),
            ],
          ),
          if (booksLoading) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            const Shimmer(
              child: ExcludeSemantics(
                child: SizedBox(
                  key: Key('series-action-skeleton'),
                  width: AppSpacing.xxl * 3,
                  height: AppSpacing.xxl,
                  child: SkeletonBox(shape: StadiumBorder()),
                ),
              ),
            ),
          ] else if (next != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            GlassPillButton(
              key: const Key('series-main-action'),
              onPressed: () => onOpenBook(next),
              icon: unstarted ? Icons.play_arrow : Icons.menu_book,
              label: unstarted
                  ? l10n.startReading
                  : l10n.continueReadingNumber(
                      next.number.isEmpty ? next.name : next.number,
                    ),
            ),
          ],
          if (!metadataLoading && summary.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            SeriesSummary(text: summary, maxLines: summaryMaxLines),
          ],
        ],
      ),
    );

    if (isEink) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.einkInk)),
        ),
        child: content,
      );
    }

    return Stack(
      children: <Widget>[
        Positioned.fill(child: SeriesHeaderBackdrop(bytes: bytes)),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const <double>[0.0, 0.55, 1.0],
                colors: <Color>[
                  theme.colorScheme.surface.withValues(alpha: 0.42),
                  theme.colorScheme.surface.withValues(alpha: 0.72),
                  theme.colorScheme.surface,
                ],
              ),
            ),
          ),
        ),
        content,
      ],
    );
  }
}
