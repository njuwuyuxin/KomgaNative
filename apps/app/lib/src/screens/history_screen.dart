import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/providers/reading_history_provider.dart';
import 'package:yomu/src/widgets/history_list.dart';
import 'package:yomu_design_system/yomu_design_system.dart';

/// 阅读历史页（HIS-02）：按天分组、可搜索、可删单条、可清理已移除条目、可清空。
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
    final snapshot = ref.watch(readingHistorySnapshotProvider);
    final all = snapshot.sessions;
    final existingLocalIds = snapshot.existingLocalIds;
    final removedIds = snapshot.removedIds;
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
                          if (removedIds.isNotEmpty)
                            GlassMenuItemButton(
                              key: const Key('history-clear-removed'),
                              label: l10n.historyClearRemoved,
                              icon: Icons.cleaning_services_outlined,
                              onPressed: () => unawaited(
                                _confirmClearRemoved(context, removedIds),
                              ),
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
              HistoryList(
                rows: rows,
                existingLocalIds: existingLocalIds,
                onDelete: (int id) => unawaited(
                  ref.read(readingSessionRecorderProvider).delete(id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDialog(
    BuildContext context, {
    required Key dialogKey,
    required Key okKey,
    required String title,
    required String body,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        key: dialogKey,
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: okKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _confirmClear(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirmDialog(
      context,
      dialogKey: const Key('history-clear-confirm'),
      okKey: const Key('history-clear-ok'),
      title: l10n.historyClearTitle,
      body: l10n.historyClearBody,
    );
    if (!ok) return;
    await ref.read(readingSessionRecorderProvider).clear();
  }

  Future<void> _confirmClearRemoved(
    BuildContext context,
    List<int> removedIds,
  ) async {
    final l10n = AppLocalizations.of(context);
    final ok = await _confirmDialog(
      context,
      dialogKey: const Key('history-clear-removed-confirm'),
      okKey: const Key('history-clear-removed-ok'),
      title: l10n.historyClearRemovedTitle,
      body: l10n.historyClearRemovedBody(removedIds.length),
    );
    if (!ok) return;
    await ref.read(readingSessionRecorderProvider).deleteMany(removedIds);
  }
}
