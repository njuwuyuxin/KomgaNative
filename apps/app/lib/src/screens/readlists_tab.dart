import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/collections_controller.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/screens/collections_screen.dart';
import 'package:yomu/src/widgets/curation_dialogs.dart';
import 'package:yomu/src/widgets/load_more_footer.dart';
import 'package:material_ui/material_ui.dart';

/// 阅读列表的本地排序方式（与收藏集对齐）。
enum ReadListSort { name, bookCount, recent }

/// 阅读列表标签页（ARC-12 增量分页 + 搜索/排序/长按管理）。
class ReadListsTab extends ConsumerStatefulWidget {
  const ReadListsTab({required this.topPadding, super.key});

  final double topPadding;

  @override
  ConsumerState<ReadListsTab> createState() => _ReadListsTabState();
}

class _ReadListsTabState extends ConsumerState<ReadListsTab> {
  String _query = '';
  ReadListSort _sort = ReadListSort.name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(readListsProvider);
    if (async.hasError && !async.hasValue) {
      return CollectionsTabError(
        topPadding: widget.topPadding,
        message: l10n.failureTitle(failureKindOf(async.error)),
        onRetry: () => ref.invalidate(readListsProvider),
      );
    }
    final value = async.value;
    if (value == null) {
      return CollectionsTabLoading(topPadding: widget.topPadding);
    }
    if (value.items.isEmpty) {
      return CollectionsTabEmpty(
        topPadding: widget.topPadding,
        icon: Icons.list_alt_outlined,
        text: l10n.readListsEmpty,
      );
    }
    final visible = _filterAndSort(value.items, _query, _sort);
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            top: widget.topPadding + AppSpacing.xs,
            left: AppSpacing.md,
            right: AppSpacing.md,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('readlists-search'),
                  onChanged: (String v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l10n.searchReadListsHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                key: const Key('readlists-sort'),
                tooltip: l10n.sort,
                onPressed: () => unawaited(_pickSort(context, l10n)),
                icon: const Icon(Icons.sort),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            edgeOffset: widget.topPadding,
            onRefresh: () async {
              ref.invalidate(readListsProvider);
              await ref.read(readListsProvider.future);
            },
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      SizedBox(height: widget.topPadding),
                      CollectionsTabEmpty(
                        topPadding: 0,
                        icon: Icons.search_off,
                        text: l10n.noMatches,
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(
                      top: AppSpacing.xs,
                      bottom: AppSizes.navBarClearance,
                    ),
                    children: <Widget>[
                      AppListGroup(
                        children: <Widget>[
                          for (final list in visible)
                            ListTile(
                              key: Key('readlist-${list.id}'),
                              leading: const Icon(Icons.list_alt_outlined),
                              title: Text(list.name),
                              subtitle: Text(
                                list.summary.isEmpty
                                    ? l10n.bookCount(list.bookCount)
                                    : '${l10n.bookCount(list.bookCount)} · '
                                          '${list.summary}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push(
                                '/readlists/${list.id}',
                                extra: list.name,
                              ),
                              onLongPress: () =>
                                  unawaited(_manageReadList(context, list)),
                            ),
                        ],
                      ),
                      LoadMoreFooter(
                        loaded: value.items.length,
                        total: value.totalElements,
                        onLoadMore: () => unawaited(
                          ref.read(readListsProvider.notifier).loadMore(),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _manageReadList(BuildContext context, ReadList list) async {
    final l10n = AppLocalizations.of(context);
    final action = await _promptManageAction(context, l10n);
    if (action == null || !context.mounted) return;
    if (action == 'edit') {
      final form = await promptReadListForm(
        context,
        title: l10n.readListEdit,
        initialName: list.name,
        initialSummary: list.summary,
      );
      if (form == null || !context.mounted) return;
      if (form.name == list.name && form.summary == list.summary) return;
      await _runWrite(
        context,
        () => ref
            .read(collectionsControllerProvider.notifier)
            .updateReadList(list.id, name: form.name, summary: form.summary),
      );
    } else if (await confirmReadListDelete(context, list.name)) {
      if (!context.mounted) return;
      await _runWrite(
        context,
        () => ref
            .read(collectionsControllerProvider.notifier)
            .deleteReadList(list.id),
      );
    }
  }

  Future<void> _runWrite(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(l10n.readListSaved)));
    } on ShelfFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<void> _pickSort(BuildContext context, AppLocalizations l10n) async {
    final picked = await showModalBottomSheet<ReadListSort>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final option in ReadListSort.values)
              ListTile(
                key: Key('readlists-sort-${option.name}'),
                title: Text(_sortLabel(l10n, option)),
                leading: Icon(
                  option == _sort
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }
}

List<ReadList> _filterAndSort(
  List<ReadList> items,
  String rawQuery,
  ReadListSort sort,
) {
  final query = rawQuery.trim().toLowerCase();
  return <ReadList>[
    for (final item in items)
      if (query.isEmpty || item.name.toLowerCase().contains(query)) item,
  ]..sort((ReadList a, ReadList b) {
    switch (sort) {
      case ReadListSort.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case ReadListSort.bookCount:
        return b.bookCount.compareTo(a.bookCount);
      case ReadListSort.recent:
        final left = a.lastModifiedDate ?? a.createdDate;
        final right = b.lastModifiedDate ?? b.createdDate;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
    }
  });
}

String _sortLabel(AppLocalizations l10n, ReadListSort option) =>
    switch (option) {
      ReadListSort.name => l10n.sortName,
      ReadListSort.bookCount => l10n.sortBookCount,
      ReadListSort.recent => l10n.sortRecent,
    };

Future<String?> _promptManageAction(
  BuildContext context,
  AppLocalizations l10n,
) => showModalBottomSheet<String>(
  context: context,
  builder: (BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          key: const Key('readlist-edit'),
          leading: const Icon(Icons.edit_outlined),
          title: Text(l10n.readListEdit),
          onTap: () => Navigator.of(context).pop('edit'),
        ),
        ListTile(
          key: const Key('readlist-delete'),
          leading: const Icon(Icons.delete_outline),
          title: Text(l10n.readListDelete),
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    ),
  ),
);
