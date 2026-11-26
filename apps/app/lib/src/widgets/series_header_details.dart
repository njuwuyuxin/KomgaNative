import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

/// 系列详情头部的标题信息、标签胶囊与可展开简介（ARC-12 拆分独立文件）。
class SeriesTitleSkeleton extends StatelessWidget {
  const SeriesTitleSkeleton({super.key});

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

class SeriesTitleBlock extends StatefulWidget {
  const SeriesTitleBlock({required this.series, super.key});

  final Series? series;

  @override
  State<SeriesTitleBlock> createState() => _SeriesTitleBlockState();
}

class _SeriesTitleBlockState extends State<SeriesTitleBlock> {
  static const int _visibleTags = 3;

  bool _showAllTags = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final series = widget.series;
    final read = series?.booksReadCount ?? 0;
    final total = series?.booksCount ?? 0;
    final facts = <String>[
      if (series != null && series.authors.isNotEmpty)
        series.authors.join(', '),
      if (series?.publisher?.trim().isNotEmpty ?? false)
        series!.publisher!.trim(),
      if (series?.releaseDate != null) '${series!.releaseDate!.year}',
    ];
    final tags = series?.tags ?? const <String>[];
    final hiddenTags = tags.length - _visibleTags;
    final shownTags = _showAllTags ? tags : tags.take(_visibleTags);

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
        if (tags.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: <Widget>[
              for (final tag in shownTags) _TagChip(label: tag),
              if (!_showAllTags && hiddenTags > 0)
                GestureDetector(
                  key: const Key('series-tags-more'),
                  onTap: () => setState(() => _showAllTags = true),
                  child: _TagChip(label: '+$hiddenTags', highlighted: true),
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

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: highlighted
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: muted),
        ),
      ),
    );
  }
}

class SeriesSummary extends StatefulWidget {
  const SeriesSummary({required this.text, required this.maxLines, super.key});

  final String text;
  final int maxLines;

  @override
  State<SeriesSummary> createState() => _SeriesSummaryState();
}

class _SeriesSummaryState extends State<SeriesSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final style = AppTypography.of(context).body
        .copyWith(color: theme.colorScheme.onSurfaceVariant);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        if (!painter.didExceedMaxLines) {
          return Text(
            widget.text,
            key: const Key('series-summary'),
            style: style,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            GestureDetector(
              key: const Key('series-summary'),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                widget.text,
                maxLines: _expanded ? null : widget.maxLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style: style,
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
      },
    );
  }
}
