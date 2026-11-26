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
import 'package:yomu/src/widgets/collection_covers.dart';
import 'package:yomu/src/widgets/curation_dialogs.dart';
import 'package:yomu/src/widgets/load_more_footer.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集列表的本地排序方式（UI-02）。
enum CollectionSort { name, seriesCount, recent }

/// 收藏集标签页（ARC-12 增量分页 + 拆分独立文件）。
class CollectionsTab extends ConsumerStatefulWidget {
  const CollectionsTab({required this.topPadding, super.key});

  final double topPadding;

  @override
  ConsumerState<CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends ConsumerState<CollectionsTab> {
  String _query = '';
  CollectionSort _sort = CollectionSort.name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(collectionsProvider);
    if (async.hasError && !async.hasValue) {
      return CollectionsTabError(
        topPadding: widget.topPadding,
        message: l10n.failureTitle(failureKindOf(async.error)),
        onRetry: () => ref.invalidate(collectionsProvider),
      );
    }
    final value = async.value;
    if (value == null) {
      return CollectionsTabLoading(topPadding: widget.topPadding);
    }
    if (value.items.isEmpty) {
      return CollectionsTabEmpty(
        topPadding: widget.topPadding,
        icon: Icons.collections_bookmark_outlined,
        text: l10n.collectionsEmpty,
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
                  key: const Key('collections-search'),
                  onChanged: (String v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l10n.searchCollectionsHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                key: const Key('collections-sort'),
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
              ref.invalidate(collectionsProvider);
              await ref.read(collectionsProvider.future);
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
                          for (final collection in visible)
                            ListTile(
                              key: Key('collection-${collection.id}'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              leading: CollectionCovers(
                                collectionId: collection.id,
                                name: collection.name,
                                seriesIds: collection.seriesIds,
                              ),
                              title: Text(collection.name),
                              subtitle: Text(
                                l10n.seriesCount(collection.seriesCount),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push(
                                '/collections/${collection.id}',
                                extra: collection.name,
                              ),
                              onLongPress: () => unawaited(
                                _manageCollection(context, collection),
                              ),
                            ),
                        ],
                      ),
                      LoadMoreFooter(
                        loaded: value.items.length,
                        total: value.totalElements,
                        onLoadMore: () => unawaited(
                          ref.read(collectionsProvider.notifier).loadMore(),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _manageCollection(
    BuildContext context,
    Collection collection,
  ) async {
    final l10n = AppLocalizations.of(context);
    final action = await _promptManageAction(context, l10n);
    if (action == null || !context.mounted) return;
    if (action == 'rename') {
      final name = await promptCollectionName(
        context,
        title: l10n.collectionRename,
        initial: collection.name,
        dialogKey: const Key('collection-rename-dialog'),
        fieldKey: const Key('collection-rename-field'),
        okKey: const Key('collection-rename-ok'),
      );
      if (name == null || name.isEmpty || name == collection.name) return;
      if (!context.mounted) return;
      await _runWrite(
        context,
        () => ref
            .read(collectionsControllerProvider.notifier)
            .rename(collection.id, name),
      );
    } else if (await confirmCollectionDelete(context, collection.name)) {
      if (!context.mounted) return;
      await _runWrite(
        context,
        () => ref
            .read(collectionsControllerProvider.notifier)
            .delete(collection.id),
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
      messenger.showSnackBar(SnackBar(content: Text(l10n.collectionSaved)));
    } on ShelfFailure catch (failure) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<void> _pickSort(BuildContext context, AppLocalizations l10n) async {
    final picked = await showModalBottomSheet<CollectionSort>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final option in CollectionSort.values)
              ListTile(
                key: Key('collections-sort-${option.name}'),
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

List<Collection> _filterAndSort(
  List<Collection> items,
  String rawQuery,
  CollectionSort sort,
) {
  final query = rawQuery.trim().toLowerCase();
  return <Collection>[
    for (final item in items)
      if (query.isEmpty || item.name.toLowerCase().contains(query)) item,
  ]..sort((Collection a, Collection b) {
    switch (sort) {
      case CollectionSort.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case CollectionSort.seriesCount:
        return b.seriesCount.compareTo(a.seriesCount);
      case CollectionSort.recent:
        final left = a.lastModifiedDate ?? a.createdDate;
        final right = b.lastModifiedDate ?? b.createdDate;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
    }
  });
}

String _sortLabel(AppLocalizations l10n, CollectionSort option) =>
    switch (option) {
      CollectionSort.name => l10n.sortName,
      CollectionSort.seriesCount => l10n.sortSeriesCount,
      CollectionSort.recent => l10n.sortRecent,
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
          key: const Key('collection-rename'),
          leading: const Icon(Icons.edit_outlined),
          title: Text(l10n.collectionRename),
          onTap: () => Navigator.of(context).pop('rename'),
        ),
        ListTile(
          key: const Key('collection-delete'),
          leading: const Icon(Icons.delete_outline),
          title: Text(l10n.collectionDelete),
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    ),
  ),
);
