import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/cross_source_reading_provider.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读历史页（HIS-02）：按天分组、可搜索、可删单条、可清空。
///
/// 数据全部来自本地 `reading_sessions`（HIS-01），不请求服务端——
/// "我什么时候读了什么"是私有信息，没必要每次都问服务器。
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _query = '';
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(readingSessionsProvider);
    final all = async.value ?? const <ReadingSession>[];
    final query = _query.trim().toLowerCase();
    final rows = <ReadingSession>[
      for (final session in all)
        if (query.isEmpty ||
            session.bookName.toLowerCase().contains(query) ||
            session.seriesId.toLowerCase().contains(query))
          session,
    ];

    return Scaffold(
      body: GlassPageBackground(
        child: CustomScrollView(
          slivers: <Widget>[
            GlassHeaderSliver(
              header: GlassHeader(
                leading: GlassIconButton(
                  icon: Icons.chevron_left,
                  label: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => context.pop(),
                ),
                bar: GlassSearchField(
                  key: const Key('history-search'),
                  controller: _controller,
                  hintText: l10n.historySearchHint,
                  clearLabel: l10n.closeSearch,
                  onChanged: (String value) => setState(() => _query = value),
                ),
                trailing: all.isEmpty
                    ? null
                    : GlassMenuButton(
                        key: const Key('history-menu'),
                        orb: true,
                        icon: Icons.more_vert,
                        label: l10n.readerMore,
                        menuChildren: <Widget>[
                          GlassMenuItemButton(
                            key: const Key('history-insights'),
                            label: l10n.insights,
                            icon: Icons.insights_outlined,
                            onPressed: () => context.push('/insights'),
                          ),
                          GlassMenuItemButton(
                            key: const Key('history-clear'),
                            label: l10n.historyClear,
                            icon: Icons.delete_sweep_outlined,
                            onPressed: () => unawaited(_confirmClear(context)),
                          ),
                        ],
                      ),
              ),
            ),
            if (all.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.history,
                          size: AppSpacing.xxl,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.historyEmpty,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.historyEmptyHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (rows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(l10n.noMatches)),
              )
            else
              _HistoryList(
                rows: rows,
                onDelete: (int id) => unawaited(
                  ref.read(readingSessionRecorderProvider).delete(id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: const Key('history-clear-confirm'),
        title: Text(l10n.historyClearTitle),
        content: Text(l10n.historyClearBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('history-clear-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(readingSessionRecorderProvider).clear();
  }
}

/// 按天分组的列表：今天 / 昨天 / 具体日期。
class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.rows, required this.onDelete});

  final List<ReadingSession> rows;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final groups = <String, List<ReadingSession>>{};
    for (final row in rows) {
      final day = DateTime(
        row.startedAt.year,
        row.startedAt.month,
        row.startedAt.day,
      );
      final key = day == today
          ? l10n.historyToday
          : (day == yesterday
                ? l10n.historyYesterday
                : '${day.year}-${_two(day.month)}-${_two(day.day)}');
      groups.putIfAbsent(key, () => <ReadingSession>[]).add(row);
    }

    return SliverPadding(
      padding: const EdgeInsets.only(bottom: AppSizes.navBarClearance),
      sliver: SliverList.list(
        children: <Widget>[
          for (final entry in groups.entries) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                entry.key,
                key: Key('history-group-${entry.key}'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            AppListGroup(
              children: <Widget>[
                for (final row in entry.value)
                  _HistoryRow(session: row, onDelete: onDelete),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.session, required this.onDelete});

  final ReadingSession session;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = session.scope.isEmpty
        ? ref.watch(bookCoverProvider(session.bookId)).value
        : ref
              .watch(
                scopedBookCoverProvider((
                  sourceKey: session.scope,
                  bookId: session.bookId,
                )),
              )
              .value;
    final minutes = session.durationMs ~/ 60000;
    final seconds = (session.durationMs % 60000) ~/ 1000;
    final duration = minutes > 0
        ? l10n.historyMinutesSeconds(minutes, _two(seconds))
        : '${seconds}s';

    return ListTile(
      key: Key('history-row-${session.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: SizedBox(
          width: AppSpacing.xl,
          height: AppSpacing.xxl,
          child: cover == null
              ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
              : CoverImage(bytes: cover),
        ),
      ),
      title: Text(
        session.bookName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        l10n.historyRow(session.startPage, session.endPage, duration),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        key: Key('history-delete-${session.id}'),
        tooltip: l10n.delete,
        icon: const Icon(Icons.close, size: AppSizes.iconSm),
        onPressed: () => onDelete(session.id),
      ),
      onTap: () => _openSessionBook(context, ref, l10n),
    );
  }

  void _openSessionBook(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final query = session.scope.isEmpty
        ? ''
        : '?source=${Uri.encodeComponent(session.scope)}';
    unawaited(context.push('/reader/${session.bookId}$query'));
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
