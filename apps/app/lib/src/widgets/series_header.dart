import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_design_system/komga_design_system.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/l10n/app_localizations.dart';
import 'package:komga_native/src/data/book_selection.dart';
import 'package:komga_native/src/providers/library_providers.dart';
import 'package:komga_native/src/widgets/series_header_cover.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情页的头部（UI-P2-4）。
///
/// 构成：**模糊放大的封面当背景**（`ImageFiltered`，不是 `BackdropFilter`——
/// 模糊的是封面自己，便宜得多，也不违反"页面里不许直接写 BackdropFilter"），
/// 上面压渐变遮罩，再放封面、标题、作者/出版社/年份、标签、可展开简介，
/// 最后是主按钮（继续阅读第 N 本 / 开始阅读）。
///
/// **加载态与内容态是同一个组件**：封面槽位（含 Hero）第一帧就在，元信息还没
/// 回来时用骨架占位。这样从书架进详情时共享元素的终点始终存在，首次打开和
/// 后续打开看到的是同一段动画，而不是"第一次全屏加载、第二次才飞"。
///
/// 墨水屏：不做模糊背景，用纯纸色 + 描边（模糊在灰阶屏上就是一团脏灰）。
class SeriesHeader extends ConsumerWidget {
  const SeriesHeader({
    required this.series,
    required this.seriesId,
    required this.heroTag,
    required this.books,
    required this.metadataLoading,
    required this.booksLoading,
    required this.onOpenBook,
    super.key,
  });

  final Series? series;
  final String seriesId;

  /// 封面 Hero tag（从货架带过来的那一份，见 `seriesHeroTag`）。
  final String heroTag;

  /// 书列表；还没回来或失败时是 null（主按钮位置按 [booksLoading] 处理）。
  final List<Book>? books;

  /// 系列元信息（标题 / 作者 / 进度）还在加载：先用骨架占位，
  /// 不要先显示 "Series / 0 of 0 read" 再跳成真数据。
  final bool metadataLoading;

  /// 书列表还在加载：主按钮位置先放骨架，避免整块区域先空着再突然出现。
  ///
  /// 与 [books] 为 null 分开判断：请求失败时也没有书，但那时不该一直转微光。
  final bool booksLoading;

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
    final books = this.books;
    final next = books == null ? null : nextBookToRead(books);
    final unstarted = books == null || isUnstartedSeries(books);
    final summary = series?.summary?.trim() ?? '';

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
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
                          child: _TitleSkeleton(
                            key: Key('series-title-skeleton'),
                          ),
                        ),
                      )
                    : _TitleBlock(series: series),
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
            _Summary(text: summary),
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
        Positioned.fill(child: SeriesHeaderBackdrop(bytes: bytes)),
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

/// 元信息未就绪时的标题区占位：标题两行 + 作者行 + 进度条的位置。
///
/// 宽度/高度都取 token，尽量贴近真实排版；即便真实标题只有一行，
/// 变化的也只是封面**下方**的高度，封面槽位不会挪位置（Hero 落点稳定）。
class _TitleSkeleton extends StatelessWidget {
  const _TitleSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          height: AppSpacing.lg,
          width: AppSpacing.xxl * 3,
          child: SkeletonBox(),
        ),
        SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: AppSpacing.md,
          width: AppSpacing.xxl * 2,
          child: SkeletonBox(),
        ),
        SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: AppSizes.progressBar,
          child: SkeletonBox(shape: StadiumBorder()),
        ),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.series});

  final Series? series;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final series = this.series;
    final read = series?.booksReadCount ?? 0;
    final total = series?.booksCount ?? 0;
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
