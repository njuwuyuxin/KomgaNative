import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reading_stats.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:material_ui/material_ui.dart';

/// Insights（HIS-03）：连续天数、最长连续、热力图、周/月汇总。
///
/// 全部来自本地 `reading_sessions`，没有服务端参与——
/// 这里回答的是"我自己读了多少"，不是"服务器上有什么"。
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({this.now, super.key});

  /// 统计口径里的"今天"。默认取系统时钟。
  ///
  /// 测试（尤其是黄金图）必须注入固定值：周/月汇总与热力图都相对"今天"算，
  /// 跟着系统时钟走的话，同一份代码在不同日期 / 时区渲染出的数字不同，
  /// 基线就会莫名其妙失配（CI 跑 UTC，本地跑 +08，跨日必红）。
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sessions = ref.watch(readingSessionsProvider).value;
    final stats = sessions == null
        ? ReadingStats.empty
        : ReadingStats.fromSessions(sessions, now: now);

    return Scaffold(
      body: GlassPageBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(
                bar: GlassSurface(
                  shape: AppShapes.of(context, AppShapes.bar),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        key: const Key('insights-back'),
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          l10n.insights,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.of(context).title,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (stats.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.insights_outlined,
                          size: AppSpacing.xxl,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.insightsEmpty,
                          key: const Key('insights-empty'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.insightsEmptyHint,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSizes.navBarClearance,
                ),
                sliver: SliverList.list(
                  children: <Widget>[
                    AppListGroup(
                      children: <Widget>[
                        _StatRow(
                          icon: Icons.local_fire_department_outlined,
                          label: l10n.insightsCurrentStreak,
                          value: l10n.insightsDays(stats.currentStreak),
                          valueKey: const Key('insights-current-streak'),
                        ),
                        _StatRow(
                          icon: Icons.emoji_events_outlined,
                          label: l10n.insightsLongestStreak,
                          value: l10n.insightsDays(stats.longestStreak),
                          valueKey: const Key('insights-longest-streak'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppListGroup(
                      header: l10n.insightsThisWeek,
                      children: <Widget>[
                        _StatRow(
                          icon: Icons.schedule,
                          label: l10n.insightsTime,
                          value: l10n.insightsMinutes(stats.weekMinutes),
                          valueKey: const Key('insights-week-minutes'),
                        ),
                        _StatRow(
                          icon: Icons.menu_book_outlined,
                          label: l10n.insightsBooks,
                          value: '${stats.weekBooks}',
                          valueKey: const Key('insights-week-books'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppListGroup(
                      header: l10n.insightsThisMonth,
                      children: <Widget>[
                        _StatRow(
                          icon: Icons.schedule,
                          label: l10n.insightsTime,
                          value: l10n.insightsMinutes(stats.monthMinutes),
                          valueKey: const Key('insights-month-minutes'),
                        ),
                        _StatRow(
                          icon: Icons.menu_book_outlined,
                          label: l10n.insightsBooks,
                          value: '${stats.monthBooks}',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        l10n.insightsHeatmap,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ReadingHeatmap(days: stats.days),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(
        value,
        key: valueKey,
        // 数字用等宽字形：连续天数从 9→10 时不会让这一行抖一下（UI-01）。
        style: AppTypography.of(context).progressNumber
            .copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

/// 热力图：12 周 × 7 天的小方块，颜色深浅表示当天阅读时长。
class ReadingHeatmap extends StatelessWidget {
  const ReadingHeatmap({required this.days, super.key});

  final List<ReadingDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (days.isEmpty) return const SizedBox.shrink();
    final maxMinutes = days
        .map((ReadingDay d) => d.minutes)
        .fold<int>(0, (int a, int b) => a > b ? a : b);
    const cell = AppSizes.heatmapCell;
    const gap = AppSpacing.xxs;

    // 每 7 天一周：按周切列，列内从上到下是周一…周日。
    final weeks = <List<ReadingDay>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, (i + 7 > days.length) ? days.length : i + 7));
    }

    return SingleChildScrollView(
      key: const Key('insights-heatmap'),
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final week in weeks)
            Padding(
              padding: const EdgeInsets.only(right: gap),
              child: Column(
                children: <Widget>[
                  for (final day in week)
                    Padding(
                      padding: const EdgeInsets.only(bottom: gap),
                      child: Container(
                        width: cell,
                        height: cell,
                        decoration: BoxDecoration(
                          color: _colorFor(day, maxMinutes, theme),
                          borderRadius: BorderRadius.circular(AppRadii.xs / 2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _colorFor(ReadingDay day, int maxMinutes, ThemeData theme) {
    if (day.minutes <= 0) {
      return theme.colorScheme.surfaceContainerHighest;
    }
    // 4 档深浅：够表达"轻度/正常/多/很多"，再多也没法分辨。
    final ratio = maxMinutes == 0 ? 1.0 : day.minutes / maxMinutes;
    final alpha = 0.25 + 0.75 * ratio.clamp(0.0, 1.0);
    return theme.colorScheme.primary.withValues(alpha: alpha);
  }
}
