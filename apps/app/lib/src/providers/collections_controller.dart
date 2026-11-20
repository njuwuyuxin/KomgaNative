import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/providers/library_providers.dart';

/// 收藏集写操作控制器（ARC-05 / ARC-09）。
class CollectionsController extends Notifier<void> {
  @override
  void build() {}

  Future<KomgaCollection> create({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  }) async {
    final created = await ref
        .read(collectionsRepositoryProvider)
        .createCollection(name: name, seriesIds: seriesIds, ordered: ordered);
    ref.invalidate(collectionsProvider);
    return created;
  }

  Future<void> rename(String collectionId, String name) async {
    await ref
        .read(collectionsRepositoryProvider)
        .renameCollection(collectionId, name);
    ref.invalidate(collectionsProvider);
  }

  Future<void> delete(String collectionId) async {
    await ref
        .read(collectionsRepositoryProvider)
        .deleteCollection(collectionId);
    ref.invalidate(collectionsProvider);
  }
}

final NotifierProvider<CollectionsController, void>
collectionsControllerProvider = NotifierProvider<CollectionsController, void>(
  CollectionsController.new,
);
