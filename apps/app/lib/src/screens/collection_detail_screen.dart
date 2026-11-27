import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_design_system/yomu_design_system.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/l10n/app_localizations.dart';
import 'package:yomu/src/data/curation_ops.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu/src/l10n/failure_text.dart';
import 'package:yomu/src/providers/collections_controller.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/pinned_series_provider.dart';
import 'package:yomu/src/widgets/curation_detail_rows.dart';
import 'package:yomu/src/widgets/curation_dialogs.dart';
import 'package:yomu/src/widgets/series_picker_sheet.dart';
import 'package:yomu/src/widgets/series_shelf_tile.dart';
import 'package:material_ui/material_ui.dart';

/// 收藏集里的系列（UI-P3-8 / ARC-12 增量分页 + 完整添加/移出/重命名/删除管理）。
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({
    required this.collectionId,
    this.title,
    super.key,
  });

  final String collectionId;
  final String? title;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  final Set<String> _hiddenIds = <String>{};

  String _displayTitle(AppLocalizations l10n, Collection? detail) =>
      detail?.name ?? widget.title ?? l10n.collectionFallback;

  List<String> _currentSeriesIds(Collection? detail, PageResult<Series>? page) {
    if (detail != null && detail.seriesIds.isNotEmpty) return detail.seriesIds;
    return <String>[for (final s in page?.items ?? const <Series>[]) s.id];
  }

  Future<void> _addSeries(Collection? detail, PageResult<Series>? page) async {
    final existing = _currentSeriesIds(detail, page).toSet();
    final picked = await showSeriesPickerSheet(context, existingIds: existing);
    if (picked == null || picked.isEmpty || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added = await ref
          .read(collectionsControllerProvider.notifier)
          .addSeries(widget.collectionId, picked);
      if (!mounted) return;
      setState(() => _hiddenIds.removeAll(picked));
      if (added > 0) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.collectionSeriesAdded(added))),
        );
      }
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<void> _rename(String currentName) async {
    final l10n = AppLocalizations.of(context);
    final name = await promptCollectionName(
      context,
      title: l10n.collectionRename,
      initial: currentName,
      dialogKey: const Key('collection-rename-dialog'),
      fieldKey: const Key('collection-rename-field'),
      okKey: const Key('collection-rename-ok'),
    );
    if (name == null || name.isEmpty || name == currentName || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .rename(widget.collectionId, name);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.collectionSaved)));
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<void> _deleteCollection(String currentName) async {
    final confirmed = await confirmCollectionDelete(context, currentName);
    if (!confirmed || !mounted) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .delete(widget.collectionId);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.collectionSaved)));
      if (GoRouter.maybeOf(context)?.canPop() ?? false) context.pop();
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
    }
  }

  Future<bool> _removeSeries(
    Series series, {
    required String displayName,
    required Collection? detail,
    required PageResult<Series>? page,
    bool fromSwipe = false,
  }) async {
    final l10n = AppLocalizations.of(context);
    final currentIds = _currentSeriesIds(detail, page);
    final remaining = removeMatchingIds(currentIds, <String>[series.id]);
    final messenger = ScaffoldMessenger.of(context);

    if (remaining.isEmpty) {
      final confirmed = await confirmDestructiveCuration(
        context,
        title: l10n.collectionRemoveLastTitle,
        body: l10n.collectionRemoveLastBody(displayName),
        confirmLabel: l10n.delete,
        dialogKey: const Key('collection-remove-last-confirm'),
        okKey: const Key('collection-remove-last-ok'),
      );
      if (!confirmed || !mounted) return false;
      try {
        await ref
            .read(collectionsControllerProvider.notifier)
            .delete(widget.collectionId);
        if (!mounted) return true;
        messenger.showSnackBar(SnackBar(content: Text(l10n.collectionSaved)));
        if (GoRouter.maybeOf(context)?.canPop() ?? false) context.pop();
        return true;
      } on ShelfFailure catch (failure) {
        if (!mounted) return false;
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.failureTitle(failure.kind))),
        );
        return false;
      }
    }

    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .updateSeries(widget.collectionId, remaining);
      if (!mounted) return true;
      if (fromSwipe) setState(() => _hiddenIds.add(series.id));
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.collectionRemoved(displayName)),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () => unawaited(_restoreSeries(currentIds, series.id)),
          ),
        ),
      );
      return true;
    } on ShelfFailure catch (failure) {
      if (!mounted) return false;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.failureTitle(failure.kind))),
      );
      return false;
    }
  }

  Future<void> _restoreSeries(
    List<String> previousIds,
    String restoredId,
  ) async {
    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .updateSeries(widget.collectionId, previousIds);
      if (mounted) setState(() => _hiddenIds.remove(restoredId));
    } on ShelfFailure catch (failure) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.failureTitle(failure.kind))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = collectionSeriesProvider(widget.collectionId);
    final async = ref.watch(provider);
    final detail = ref
        .watch(collectionDetailProvider(widget.collectionId))
        .value;
    final displayName = _displayTitle(l10n, detail);
    final pinnedIds =
        ref
            .watch(
              detail != null
                  ? pinnedSeriesIdsForSourceProvider(detail.sourceKey)
                  : pinnedSeriesIdsProvider,
            )
            .value
            ?.toSet() ??
        const <String>{};

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
                title: Text(displayName),
                trailing: GlassMenuButton(
                  key: const Key('collection-detail-menu'),
                  orb: true,
                  icon: Icons.more_horiz,
                  label: l10n.moreActions,
                  menuChildren: <Widget>[
                    GlassMenuItemButton(
                      key: const Key('collection-add-series'),
                      label: l10n.addSeriesToCollection,
                      onPressed: () =>
                          unawaited(_addSeries(detail, async.value)),
                    ),
                    GlassMenuItemButton(
                      key: const Key('collection-detail-rename'),
                      label: l10n.collectionRename,
                      onPressed: () => unawaited(_rename(displayName)),
                    ),
                    GlassMenuItemButton(
                      key: const Key('collection-detail-delete'),
                      label: l10n.collectionDelete,
                      onPressed: () =>
                          unawaited(_deleteCollection(displayName)),
                    ),
                  ],
                ),
              ),
            ),
            CollectionSeriesSliver(
              collectionId: widget.collectionId,
              async: async,
              hiddenIds: _hiddenIds,
              onRetry: () => ref.invalidate(provider),
              onLoadMore: () =>
                  unawaited(ref.read(provider.notifier).loadMore()),
              onRemove: (Series series, {bool fromSwipe = false}) =>
                  _removeSeries(
                    series,
                    displayName: displayName,
                    detail: detail,
                    page: async.value,
                    fromSwipe: fromSwipe,
                  ),
              onLongPressSeries:
                  (BuildContext ctx, Series series, String heroTag) =>
                      showSeriesMenu(
                        ctx,
                        ref,
                        series,
                        heroTag: heroTag,
                        pinned: pinnedIds.contains(series.id),
                        onRemoveFromCollection: () async {
                          await _removeSeries(
                            series,
                            displayName: displayName,
                            detail: detail,
                            page: async.value,
                          );
                        },
                      ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSizes.navBarClearance),
            ),
          ],
        ),
      ),
    );
  }
}
