import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/library_repository.dart';
import 'package:yomu/src/data/progress/progress_sync_service.dart';
import 'package:yomu/src/data/shelf_failure.dart';

/// 收藏集与阅读列表限界上下文仓库（UI-P3-8 / SER-04 / ARC-09）。
abstract interface class CollectionsRepository {
  Future<PageResult<KomgaCollection>> collections({
    int page = 0,
    int size = 20,
  });

  Future<KomgaCollection?> collectionById(String collectionId);

  Future<List<KomgaCollection>> seriesCollections(String seriesId);

  /// 新建收藏集：必须至少带一个系列（Komga 实测拒绝空集合）。
  Future<KomgaCollection> createCollection({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  });

  Future<void> renameCollection(String collectionId, String name);

  Future<void> updateCollection(
    String collectionId, {
    String? name,
    bool? ordered,
    List<String>? seriesIds,
  });

  Future<void> deleteCollection(String collectionId);

  Future<PageResult<Series>> collectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  });

  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20});

  Future<ReadList?> readListById(String readListId);

  Future<List<ReadList>> bookReadLists(String bookId);

  /// 新建阅读列表：必须至少带一本书（Komga 实测拒绝空列表）。
  Future<ReadList> createReadList({
    required String name,
    String summary = '',
    required List<String> bookIds,
    bool ordered = false,
  });

  Future<void> updateReadList(
    String readListId, {
    String? name,
    String? summary,
    bool? ordered,
    List<String>? bookIds,
  });

  Future<void> deleteReadList(String readListId);

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

  String get _sourceKey => _session.address.baseUrl;

  @override
  Future<PageResult<KomgaCollection>> collections({
    int page = 0,
    int size = 20,
  }) async {
    try {
      final result = await _session.fetchCollections(page: page, size: size);
      return PageResult<KomgaCollection>(
        items: <KomgaCollection>[
          for (final c in result.items) c.withSource(_sourceKey),
        ],
        totalElements: result.totalElements,
        page: result.page,
        size: result.size,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<KomgaCollection?> collectionById(String collectionId) async {
    try {
      final c = await _session.fetchCollection(collectionId);
      return c.withSource(_sourceKey);
    } on KomgaNotFoundError {
      return null;
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<List<KomgaCollection>> seriesCollections(String seriesId) async {
    try {
      final items = await _session.fetchSeriesCollections(seriesId);
      return <KomgaCollection>[for (final c in items) c.withSource(_sourceKey)];
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
      final created = await _session.createCollection(
        name: name,
        seriesIds: seriesIds,
        ordered: ordered,
      );
      return created.withSource(_sourceKey);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<void> renameCollection(String collectionId, String name) =>
      updateCollection(collectionId, name: name);

  @override
  Future<void> updateCollection(
    String collectionId, {
    String? name,
    bool? ordered,
    List<String>? seriesIds,
  }) async {
    try {
      await _session.updateCollection(
        collectionId,
        name: name,
        ordered: ordered,
        seriesIds: seriesIds,
      );
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
      final result = await _session.fetchCollectionSeries(
        collectionId,
        page: page,
        size: size,
      );
      return PageResult<Series>(
        items: <Series>[for (final s in result.items) s.withSource(_sourceKey)],
        totalElements: result.totalElements,
        page: result.page,
        size: result.size,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20}) async {
    try {
      final result = await _session.fetchReadLists(page: page, size: size);
      return PageResult<ReadList>(
        items: <ReadList>[
          for (final r in result.items) r.withSource(_sourceKey),
        ],
        totalElements: result.totalElements,
        page: result.page,
        size: result.size,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<ReadList?> readListById(String readListId) async {
    try {
      final r = await _session.fetchReadList(readListId);
      return r.withSource(_sourceKey);
    } on KomgaNotFoundError {
      return null;
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<List<ReadList>> bookReadLists(String bookId) async {
    try {
      final items = await _session.fetchBookReadLists(bookId);
      return <ReadList>[for (final r in items) r.withSource(_sourceKey)];
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<ReadList> createReadList({
    required String name,
    String summary = '',
    required List<String> bookIds,
    bool ordered = false,
  }) async {
    try {
      final created = await _session.createReadList(
        name: name,
        summary: summary,
        bookIds: bookIds,
        ordered: ordered,
      );
      return created.withSource(_sourceKey);
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<void> updateReadList(
    String readListId, {
    String? name,
    String? summary,
    bool? ordered,
    List<String>? bookIds,
  }) async {
    try {
      await _session.updateReadList(
        readListId,
        name: name,
        summary: summary,
        ordered: ordered,
        bookIds: bookIds,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }

  @override
  Future<void> deleteReadList(String readListId) async {
    try {
      await _session.deleteReadList(readListId);
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
      final overlaid = await overlayBooksPage(_sync, result, scope: _sourceKey);
      return PageResult<Book>(
        items: <Book>[for (final b in overlaid.items) b.withSource(_sourceKey)],
        totalElements: overlaid.totalElements,
        page: overlaid.page,
        size: overlaid.size,
      );
    } on KomgaError catch (error) {
      throw shelfFailureOf(error);
    }
  }
}
