import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/library_providers.dart';

/// 收藏集写操作控制器（ARC-05）。
///
/// 承接新建、改名、删除意图并统一失效 [collectionsProvider]，
/// 使 Widget 层只派发控制器方法、不直接编排仓库 I/O。
class CollectionsController extends Notifier<void> {
  @override
  void build() {}

  Future<KomgaCollection> create({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  }) async {
    final created = await ref
        .read(libraryRepositoryProvider)
        .createCollection(name: name, seriesIds: seriesIds, ordered: ordered);
    ref.invalidate(collectionsProvider);
    return created;
  }

  Future<void> rename(String collectionId, String name) async {
    await ref
        .read(libraryRepositoryProvider)
        .renameCollection(collectionId, name);
    ref.invalidate(collectionsProvider);
  }

  Future<void> delete(String collectionId) async {
    await ref.read(libraryRepositoryProvider).deleteCollection(collectionId);
    ref.invalidate(collectionsProvider);
  }
}

final NotifierProvider<CollectionsController, void>
collectionsControllerProvider = NotifierProvider<CollectionsController, void>(
  CollectionsController.new,
);
