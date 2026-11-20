import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/data/library_repository.dart';
import 'package:komga_native/src/data/progress/progress_sync_service.dart';
import 'package:komga_native/src/data/shelf_failure.dart';

/// 收藏集与阅读列表限界上下文仓库（UI-P3-8 / SER-04 / ARC-09）。
abstract interface class CollectionsRepository {
  Future<PageResult<KomgaCollection>> collections({
    int page = 0,
    int size = 20,
  });

  /// 新建收藏集：必须至少带一个系列（Komga 实测拒绝空集合）。
  Future<KomgaCollection> createCollection({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  });

  Future<void> renameCollection(String collectionId, String name);

  Future<void> deleteCollection(String collectionId);

  Future<PageResult<Series>> collectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  });

  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20});

  Future<PageResult<Book>> readListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  });
}

class KomgaCollectionsRepository implements CollectionsRepository {
  const KomgaCollectionsRepository(this._session, this._sync);

  final KomgaSession _session;
  final ProgressSyncService _sync;

  KomgaSession get debugSession => _session;

  @override
  Future<PageResult<KomgaCollection>> collections({
    int page = 0,
    int size = 20,
  }) async {
    try {
      return await _session.fetchCollections(page: page, size: size);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<KomgaCollection> createCollection({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  }) async {
    try {
      return await _session.createCollection(
        name: name,
        seriesIds: seriesIds,
        ordered: ordered,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<void> renameCollection(String collectionId, String name) async {
    try {
      await _session.renameCollection(collectionId, name);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<void> deleteCollection(String collectionId) async {
    try {
      await _session.deleteCollection(collectionId);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<Series>> collectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  }) async {
    try {
      return await _session.fetchCollectionSeries(
        collectionId,
        page: page,
        size: size,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20}) async {
    try {
      return await _session.fetchReadLists(page: page, size: size);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<Book>> readListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  }) async {
    try {
      final result = await _session.fetchReadListBooks(
        readListId,
        page: page,
        size: size,
      );
      return await overlayBooksPage(_sync, result);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }
}
