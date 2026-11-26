import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/widgets/cover_image.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 阅读历史按天分组列表：今天 / 昨天 / 具体日期。
class HistoryList extends StatelessWidget {
  const HistoryList({
    required this.rows,
    required this.existingLocalIds,
    required this.onDelete,
    super.key,
  });

  final List<ReadingSession> rows;
  final Set<String>? existingLocalIds;
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
                  _HistoryRow(
                    session: row,
                    removed: isRemovedLocalSession(row, existingLocalIds),
                    onDelete: onDelete,
                  ),
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
  const _HistoryRow({
    required this.session,
    required this.removed,
    required this.onDelete,
  });

  final ReadingSession session;
  final bool removed;
  final ValueChanged<int> onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = removed
        ? null
        : ref
              .watch(
                bookCoverProvider((
                  sourceKey: session.scope.isEmpty ? null : session.scope,
                  id: session.bookId,
                )),
              )
              .value;
    final minutes = session.durationMs ~/ 60000;
    final seconds = (session.durationMs % 60000) ~/ 1000;
    final duration = minutes > 0
        ? l10n.historyMinutesSeconds(minutes, _two(seconds))
        : '${seconds}s';
    final detail = l10n.historyRow(
      session.startPage,
      session.endPage,
      duration,
    );

    return ListTile(
      key: Key('history-row-${session.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: SizedBox(
          width: AppSpacing.xl,
          height: AppSpacing.xxl,
          child: cover != null
              ? CoverImage(bytes: cover)
              : ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: removed
                      ? Center(
                          child: Icon(
                            Icons.auto_stories_outlined,
                            size: AppSizes.iconSm,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                ),
        ),
      ),
      title: Text(
        session.bookName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: removed
            ? theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: Text(
        removed ? '$detail · ${l10n.historyBookRemoved}' : detail,
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
      onTap: removed ? null : () => _openSessionBook(context),
    );
  }

  void _openSessionBook(BuildContext context) {
    final query = session.scope.isEmpty
        ? ''
        : '?source=${Uri.encodeComponent(session.scope)}';
    unawaited(context.push('/reader/${session.bookId}$query'));
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
