import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/curation_ops.dart';
import 'package:yomu/src/providers/library_providers.dart';
import 'package:yomu/src/providers/source_scoped_providers.dart';

/// 收藏集与阅读列表写操作控制器（ARC-05 / ARC-09）。
class CollectionsController extends Notifier<void> {
  @override
  void build() {}

  // ── 收藏集（系列维度） ──────────────────────────────────────────

  Future<KomgaCollection> create({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
    String? sourceKey,
  }) async {
    final created = await ref
        .read(collectionsRepositoryForSourceProvider(sourceKey))
        .createCollection(name: name, seriesIds: seriesIds, ordered: ordered);
    _invalidateCollections(seriesIds: seriesIds, sourceKey: sourceKey);
    return created;
  }

  Future<void> rename(
    String collectionId,
    String name, {
    String? sourceKey,
  }) async {
    await ref
        .read(collectionsRepositoryForSourceProvider(sourceKey))
        .renameCollection(collectionId, name);
    _invalidateCollections(
      collectionIds: <String>[collectionId],
      sourceKey: sourceKey,
    );
  }

  Future<void> updateSeries(
    String collectionId,
    List<String> seriesIds, {
    String? sourceKey,
  }) async {
    await ref
        .read(collectionsRepositoryForSourceProvider(sourceKey))
        .updateCollection(collectionId, seriesIds: seriesIds);
    _invalidateCollections(
      collectionIds: <String>[collectionId],
      invalidateAllSeriesCollections: true,
      sourceKey: sourceKey,
    );
  }

  /// 向收藏集追加系列（自动去重并保留原有顺序），返回实际新增数量。
  Future<int> addSeries(
    String collectionId,
    List<String> seriesIdsToAdd, {
    String? sourceKey,
  }) async {
    final repo = ref.read(collectionsRepositoryForSourceProvider(sourceKey));
    final current = await repo.collectionById(collectionId);
    final existing = current?.seriesIds ?? const <String>[];
    final next = mergeUniqueIds(existing, seriesIdsToAdd);
    final added = next.length - existing.length;
    if (added <= 0) return 0;
    await repo.updateCollection(collectionId, seriesIds: next);
    _invalidateCollections(
      collectionIds: <String>[collectionId],
      seriesIds: seriesIdsToAdd,
      sourceKey: sourceKey,
    );
    return added;
  }

  /// 执行勾选面板生成的收藏集变更计划（更新 + 删除变空项）。
  Future<void> applyCollectionPlan(
    MembershipChangePlan plan, {
    List<String> affectedSeriesIds = const <String>[],
    String? sourceKey,
  }) async {
    final repo = ref.read(collectionsRepositoryForSourceProvider(sourceKey));
    final touched = <String>[];
    for (final update in plan.updates) {
      await repo.updateCollection(update.id, seriesIds: update.nextIds);
      touched.add(update.id);
    }
    for (final deletion in plan.deletions) {
      await repo.deleteCollection(deletion.id);
      touched.add(deletion.id);
    }
    _invalidateCollections(
      collectionIds: touched,
      seriesIds: affectedSeriesIds,
      sourceKey: sourceKey,
    );
  }

  Future<void> delete(String collectionId, {String? sourceKey}) async {
    await ref
        .read(collectionsRepositoryForSourceProvider(sourceKey))
        .deleteCollection(collectionId);
    _invalidateCollections(
      collectionIds: <String>[collectionId],
      invalidateAllSeriesCollections: true,
      sourceKey: sourceKey,
    );
  }

  void _invalidateCollections({
    List<String> collectionIds = const <String>[],
    List<String> seriesIds = const <String>[],
    bool invalidateAllSeriesCollections = false,
    String? sourceKey,
  }) {
    ref.invalidate(collectionsProvider);
    ref.invalidate(allCollectionsProvider);
    ref.invalidate(allCollectionsForSourceProvider);
    for (final id in collectionIds) {
      ref.invalidate(collectionDetailProvider(id));
      ref.invalidate(collectionSeriesProvider(id));
    }
    if (invalidateAllSeriesCollections || sourceKey == null) {
      ref.invalidate(seriesCollectionsProvider);
    } else {
      for (final id in seriesIds) {
        ref.invalidate(
          seriesCollectionsProvider((sourceKey: sourceKey, seriesId: id)),
        );
      }
    }
  }

  // ── 阅读列表（书籍维度） ──────────────────────────────────────────

  Future<ReadList> createReadList({
    required String name,
    String summary = '',
    required List<String> bookIds,
    bool ordered = false,
    String? sourceKey,
  }) async {
    final created = await ref
        .read(collectionsRepositoryForSourceProvider(sourceKey))
        .createReadList(
          name: name,
          summary: summary,
          bookIds: bookIds,
          ordered: ordered,
        );
    _invalidateReadLists();
    return created;
  }

  Future<void> updateReadList(
    String readListId, {
    String? name,
    String? summary,
    bool? ordered,
    List<String>? bookIds,
    String? sourceKey,
  }) async {
    await ref
        .read(collectionsRepositoryForSourceProvider(sourceKey))
        .updateReadList(
          readListId,
          name: name,
          summary: summary,
          ordered: ordered,
          bookIds: bookIds,
        );
    _invalidateReadLists(readListIds: <String>[readListId]);
  }

  /// 执行勾选面板生成的阅读列表变更计划（更新 + 删除变空项）。
  Future<void> applyReadListPlan(
    MembershipChangePlan plan, {
    String? sourceKey,
  }) async {
    final repo = ref.read(collectionsRepositoryForSourceProvider(sourceKey));
    final touched = <String>[];
    for (final update in plan.updates) {
      await repo.updateReadList(update.id, bookIds: update.nextIds);
      touched.add(update.id);
    }
    for (final deletion in plan.deletions) {
      await repo.deleteReadList(deletion.id);
      touched.add(deletion.id);
    }
    _invalidateReadLists(readListIds: touched);
  }

  Future<void> deleteReadList(String readListId, {String? sourceKey}) async {
    await ref
        .read(collectionsRepositoryForSourceProvider(sourceKey))
        .deleteReadList(readListId);
    _invalidateReadLists(readListIds: <String>[readListId]);
  }

  void _invalidateReadLists({List<String> readListIds = const <String>[]}) {
    ref.invalidate(readListsProvider);
    ref.invalidate(allReadListsProvider);
    ref.invalidate(allReadListsForSourceProvider);
    for (final id in readListIds) {
      ref.invalidate(readListDetailProvider(id));
      ref.invalidate(readListBooksProvider(id));
    }
  }
}

final NotifierProvider<CollectionsController, void>
collectionsControllerProvider = NotifierProvider<CollectionsController, void>(
  CollectionsController.new,
);
