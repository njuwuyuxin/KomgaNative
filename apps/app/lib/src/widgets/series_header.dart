import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/book_selection.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/cover_image.dart';
import 'package:komga_native/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情页的头部（UI-P2-4）。
///
/// 构成：**模糊放大的封面当背景**（`ImageFiltered`，不是 `BackdropFilter`——
/// 模糊的是封面自己，便宜得多，也不违反"页面里不许直接写 BackdropFilter"），
/// 上面压渐变遮罩，再放封面、标题、作者/出版社/年份、标签、可展开简介，
/// 最后是主按钮（继续阅读第 N 本 / 开始阅读）。
///
/// 墨水屏：不做模糊背景，用纯纸色 + 描边（模糊在灰阶屏上就是一团脏灰）。
class SeriesHeader extends ConsumerWidget {
  const SeriesHeader({
    required this.series,
    required this.seriesId,
    required this.books,
    required this.onOpenBook,
    super.key,
  });

  final Series? series;
  final String seriesId;

  /// 书列表：主按钮要知道"下一本该读哪本"。
  final List<Book> books;

  final void Function(Book book) onOpenBook;

  /// 简介折叠时最多显示几行。
  static const int _summaryLines = 4;

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
    final read = series?.booksReadCount ?? 0;
    final total = series?.booksCount ?? 0;
    final next = nextBookToRead(books);
    final unstarted = isUnstartedSeries(books);

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Cover(bytes: bytes, seriesId: seriesId),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _TitleBlock(
                  series: series,
                  seriesId: seriesId,
                  read: read,
                  total: total,
                ),
              ),
            ],
          ),
          if (next != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const Key('series-main-action'),
              onPressed: () => onOpenBook(next),
              icon: Icon(unstarted ? Icons.play_arrow : Icons.menu_book),
              label: Text(
                unstarted
                    ? l10n.startReading
                    : l10n.continueReadingNumber(
                        next.number.isEmpty ? next.name : next.number,
                      ),
              ),
            ),
          ],
          if (series?.summary?.trim().isNotEmpty ?? false) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            _Summary(text: series!.summary!.trim()),
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
        // 背景：同一张封面放大 + 模糊，压一层暗渐变让文字可读。
        Positioned.fill(
          child: bytes == null
              ? const ColoredBox(color: Colors.black12)
              : _BlurredCover(bytes: bytes),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  theme.colorScheme.surface.withValues(alpha: 0.72),
                  theme.colorScheme.surface.withValues(alpha: 0.94),
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

/// 模糊放大的封面背景。
class _BlurredCover extends StatelessWidget {
  const _BlurredCover({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Transform.scale(
          // 放大一点，避免模糊后边缘露出底色。
          scale: 1.2,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.bytes, required this.seriesId});

  final Uint8List? bytes;
  final String seriesId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = AppShapes.of(context, AppShapes.panel);
    final box = SizedBox(
      width: AppSpacing.xxl * 2,
      height: AppSpacing.xxl * 3,
      child: bytes == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            )
          : CoverImage(bytes: bytes!),
    );
    final cover = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: AppShadows.of(context, AppShadows.cover),
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: box,
      ),
    );
    if (AppTheme.isEink(theme)) return cover;
    return Hero(tag: seriesHeroTag(seriesId), child: cover);
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.series,
    required this.seriesId,
    required this.read,
    required this.total,
  });

  final Series? series;
  final String seriesId;
  final int read;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final series = this.series;
    final facts = <String>[
      if (series != null && series.authors.isNotEmpty)
        series.authors.join(', '),
      if (series?.publisher?.trim().isNotEmpty ?? false)
        series!.publisher!.trim(),
      if (series?.releaseDate != null) '${series!.releaseDate!.year}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          series?.title ?? l10n.seriesFallbackTitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.of(context).title,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          l10n.readOfTotal(read, total),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        if (facts.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            facts.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
        if (series != null && series.tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final tag in series.tags.take(4))
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: const StadiumBorder(),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    child: Text(
                      tag,
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: LinearProgressIndicator(
            value: series?.progress ?? 0,
            minHeight: AppSizes.progressBar,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// 简介：默认折到 [SeriesHeader._summaryLines] 行，可展开。
class _Summary extends StatefulWidget {
  const _Summary({required this.text});

  final String text;

  @override
  State<_Summary> createState() => _SummaryState();
}

class _SummaryState extends State<_Summary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        GestureDetector(
          key: const Key('series-summary'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            widget.text,
            maxLines: _expanded ? null : SeriesHeader._summaryLines,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: AppTypography.of(context).body
                .copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        TextButton(
          key: const Key('series-summary-toggle'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(AppSizes.minTouch, AppSizes.minTouch),
            alignment: Alignment.centerLeft,
          ),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(_expanded ? l10n.showLess : l10n.showMore),
        ),
      ],
    );
  }
}
