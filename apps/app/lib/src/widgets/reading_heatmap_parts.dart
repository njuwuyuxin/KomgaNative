import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reading_stats.dart';
import 'package:yomu/src/widgets/reading_day_books_section.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 热力图顶部的月份轴（每月首周对齐，窄距自动避让防重叠）。
class HeatmapMonthAxis extends StatelessWidget {
  const HeatmapMonthAxis({
    required this.weeks,
    required this.cellSize,
    required this.gap,
    required this.maxWidth,
    super.key,
  });

  final List<List<ReadingDay?>> weeks;
  final double cellSize;
  final double gap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';
    final labels = <({int col, String text})>[];
    var lastLabeledCol = -4;

    for (var col = 0; col < weeks.length; col++) {
      final week = weeks[col];
      ReadingDay? anchor;
      if (col == 0) {
        final nextHasMonthStart =
            weeks.length > 1 &&
            weeks[1].any((ReadingDay? d) => d != null && d.date.day == 1);
        if (!nextHasMonthStart) {
          anchor = week.firstWhere(
            (ReadingDay? d) => d != null,
            orElse: () => null,
          );
        }
      } else {
        for (final day in week) {
          if (day != null && day.date.day == 1) {
            anchor = day;
            break;
          }
        }
      }
      if (anchor == null) continue;
      if (col - lastLabeledCol < 2) continue;
      final left = col * (cellSize + gap);
      if (maxWidth - left < AppSpacing.xl) continue;
      labels.add((col: col, text: _shortMonth(anchor.date.month, isZh: isZh)));
      lastLabeledCol = col;
    }

    return SizedBox(
      height: AppSizes.iconXs,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          for (final item in labels)
            Positioned(
              left: item.col * (cellSize + gap),
              top: 0,
              child: Text(
                item.text,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _shortMonth(int month, {required bool isZh}) {
    if (isZh) return '$month月';
    const names = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return names[(month - 1).clamp(0, 11)];
  }
}

/// 热力图单日方块（含未选中细描边与选中双层聚焦环）。
class HeatmapCell extends StatelessWidget {
  const HeatmapCell({
    required this.day,
    required this.maxMinutes,
    required this.selected,
    required this.eink,
    required this.onTap,
    super.key,
  });

  final ReadingDay? day;
  final int maxMinutes;
  final bool selected;
  final bool eink;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final current = day;
    if (current == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final level = ReadingStats.heatmapLevel(current, maxMinutes);
    final iso = formatIsoDate(current.date);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: '$iso, ${l10n.insightsMinutes(current.minutes)}',
      child: GestureDetector(
        key: Key('heatmap-day-$iso'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(AppHaptics.selection());
          onTap(current.date);
        },
        child: selected
            ? Container(
                padding: const EdgeInsets.all(AppSizes.hairline),
                decoration: BoxDecoration(
                  color: eink
                      ? AppTheme.einkPaper
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: eink
                      ? BorderRadius.zero
                      : BorderRadius.circular(AppRadii.xs / 2),
                  border: Border.all(
                    color: eink
                        ? AppTheme.einkInk
                        : theme.colorScheme.onSurface,
                    width: AppSpacing.xxs,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: heatmapLevelColor(level, theme, eink: eink),
                    borderRadius: eink
                        ? BorderRadius.zero
                        : BorderRadius.circular(AppRadii.xs / 4),
                  ),
                ),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  color: heatmapLevelColor(level, theme, eink: eink),
                  borderRadius: eink
                      ? BorderRadius.zero
                      : BorderRadius.circular(AppRadii.xs / 2),
                  border: Border.all(
                    color: heatmapCellBorderColor(level, theme, eink: eink),
                    width: AppSizes.hairline,
                  ),
                ),
              ),
      ),
    );
  }
}

/// 右下角 GitHub 样式 5 档色阶图例（少 □□□□□ 多）。
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({
    required this.lessLabel,
    required this.moreLabel,
    required this.eink,
    super.key,
  });

  final String lessLabel;
  final String moreLabel;
  final bool eink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Text(lessLabel, style: labelStyle),
        const SizedBox(width: AppSpacing.xs),
        for (var level = 0; level <= 4; level++) ...<Widget>[
          if (level > 0) const SizedBox(width: AppSpacing.xxs),
          Container(
            width: AppSizes.skeletonLineSm,
            height: AppSizes.skeletonLineSm,
            decoration: BoxDecoration(
              color: heatmapLevelColor(level, theme, eink: eink),
              borderRadius: eink
                  ? BorderRadius.zero
                  : BorderRadius.circular(AppRadii.xs / 2),
              border: Border.all(
                color: heatmapCellBorderColor(level, theme, eink: eink),
                width: AppSizes.hairline,
              ),
            ),
          ),
        ],
        const SizedBox(width: AppSpacing.xs),
        Text(moreLabel, style: labelStyle),
      ],
    );
  }
}

Color heatmapLevelColor(int level, ThemeData theme, {required bool eink}) {
  if (eink) {
    if (level <= 0) return AppTheme.einkPaper;
    const alphas = <double>[0.22, 0.48, 0.74, 1.0];
    return AppTheme.einkInk.withValues(alpha: alphas[level - 1]);
  }
  final scheme = theme.colorScheme;
  if (level <= 0) {
    final isDark = theme.brightness == Brightness.dark;
    return scheme.surfaceContainerHighest.withValues(
      alpha: isDark ? 0.55 : 0.78,
    );
  }
  const alphas = <double>[0.28, 0.52, 0.76, 1.0];
  return scheme.primary.withValues(alpha: alphas[level - 1]);
}

Color heatmapCellBorderColor(int level, ThemeData theme, {required bool eink}) {
  if (eink) {
    return level <= 0
        ? AppTheme.einkMuted.withValues(alpha: 0.45)
        : AppTheme.einkInk;
  }
  return theme.colorScheme.outlineVariant.withValues(
    alpha: level <= 0 ? 0.45 : 0.2,
  );
}
