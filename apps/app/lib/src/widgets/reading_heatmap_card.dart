import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reading_stats.dart';
import 'package:yomu/src/widgets/reading_day_books_section.dart';
import 'package:yomu/src/widgets/reading_heatmap_parts.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// GitHub 样式阅读热力图卡片 + 选中日期读过的书明细。
///
/// 复用 [AppListGroup] 与上方统计卡片保持完全一致的左右边距和表面材质；
/// 方块网格按可用宽度自适应周数并横向撑满，不出现右侧留白或参差不齐。
class ReadingHeatmapCard extends StatelessWidget {
  const ReadingHeatmapCard({
    required this.stats,
    required this.today,
    required this.selectedDate,
    required this.onSelectDate,
    required this.existingLocalIds,
    super.key,
  });

  final ReadingStats stats;
  final DateTime today;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final Set<String>? existingLocalIds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // AppListGroup 外边距左右各 md + 卡片内边距左右各 md。
        final gridWidth = constraints.maxWidth - AppSpacing.md * 4;
        final weekCount = ReadingStats.heatmapWeekCountForWidth(
          gridWidth,
          cellTarget: AppSizes.iconLg,
          gap: AppSpacing.xs,
        );
        final weeks = stats.heatmapWeeks(today: today, weeks: weekCount);
        final activeDate = selectedDate ?? stats.latestActiveDate;
        final selectedDay = activeDate == null ? null : stats.dayOf(activeDate);

        return AppListGroup(
          header: l10n.insightsHeatmapWeeks(weekCount),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ReadingHeatmap(
                weeks: weeks,
                selectedDate: activeDate,
                onSelectDate: onSelectDate,
              ),
            ),
            if (selectedDay != null)
              ReadingDayBooksSection(
                day: selectedDay,
                existingLocalIds: existingLocalIds,
              ),
          ],
        );
      },
    );
  }
}

/// GitHub 样式热力图网格：顶部月份标签 + 7 行自然周格子（横向撑满）+ 底部色阶图例。
class ReadingHeatmap extends StatelessWidget {
  const ReadingHeatmap({
    required this.weeks,
    required this.selectedDate,
    required this.onSelectDate,
    super.key,
  });

  final List<List<ReadingDay?>> weeks;
  final DateTime? selectedDate;
  final ValueChanged<DateTime> onSelectDate;

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final eink = AppTheme.isEink(theme);
    const gap = AppSpacing.xs;

    var maxMinutes = 0;
    for (final week in weeks) {
      for (final day in week) {
        if (day != null && day.minutes > maxMinutes) {
          maxMinutes = day.minutes;
        }
      }
    }

    return LayoutBuilder(
      key: const Key('insights-heatmap'),
      builder: (BuildContext context, BoxConstraints constraints) {
        final colCount = weeks.length;
        final cellSize =
            (constraints.maxWidth - gap * (colCount - 1)) / colCount;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            HeatmapMonthAxis(
              weeks: weeks,
              cellSize: cellSize,
              gap: gap,
              maxWidth: constraints.maxWidth,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var col = 0; col < colCount; col++) ...<Widget>[
                  if (col > 0) const SizedBox(width: gap),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        for (var row = 0; row < 7; row++) ...<Widget>[
                          if (row > 0) const SizedBox(height: gap),
                          AspectRatio(
                            aspectRatio: 1,
                            child: HeatmapCell(
                              day: weeks[col][row],
                              maxMinutes: maxMinutes,
                              selected:
                                  weeks[col][row] != null &&
                                  weeks[col][row]!.date == selectedDate,
                              eink: eink,
                              onTap: onSelectDate,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            HeatmapLegend(
              lessLabel: l10n.insightsHeatmapLess,
              moreLabel: l10n.insightsHeatmapMore,
              eink: eink,
            ),
          ],
        );
      },
    );
  }
}
