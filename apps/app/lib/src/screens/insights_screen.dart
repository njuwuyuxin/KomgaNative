import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/reading_stats.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/widgets/reading_heatmap_card.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// Insights（HIS-03）：连续天数、最长连续、GitHub 样式热力图、周/月汇总。
///
/// 全部来自本地 `reading_sessions`，没有服务端参与——
/// 这里回答的是"我自己读了多少"，不是"服务器上有什么"。
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({this.now, super.key});

  /// 统计口径里的"今天"。默认取系统时钟。
  ///
  /// 测试（尤其是黄金图）必须注入固定值：周/月汇总与热力图都相对"今天"算，
  /// 跟着系统时钟走的话，同一份代码在不同日期 / 时区渲染出的数字不同，
  /// 基线就会莫名其妙失配（CI 跑 UTC，本地跑 +08，跨日必红）。
  final DateTime? now;

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  DateTime? _selectedDate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = ReadingStats.dateOnly(widget.now ?? DateTime.now());
    final sessions = ref.watch(readingSessionsProvider).value;
    final stats = sessions == null
        ? ReadingStats.empty
        : ReadingStats.fromSessions(sessions, now: widget.now);
    final hasLocal =
        sessions?.any(
          (ReadingSession session) => isLocalSourceKey(session.scope),
        ) ??
        false;
    final existingLocalIds = hasLocal
        ? ref.watch(existingLocalBookIdsProvider).value
        : null;

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
                          key: const Key('insights-title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.of(context).title
                              .copyWith(fontWeight: FontWeight.w400),
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
                  0,
                  AppSpacing.sm,
                  0,
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
                    ReadingHeatmapCard(
                      stats: stats,
                      today: today,
                      selectedDate: _selectedDate,
                      onSelectDate: (DateTime date) =>
                          setState(() => _selectedDate = date),
                      existingLocalIds: existingLocalIds,
                    ),
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
