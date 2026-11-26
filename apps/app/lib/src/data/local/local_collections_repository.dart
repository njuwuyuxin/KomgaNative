import 'package:yomu/src/data/collections_repository.dart';
import 'package:yomu/src/data/local/local_curation_dao.dart';
import 'package:yomu/src/data/progress/progress_database.dart';
import 'package:yomu/src/data/shelf_failure.dart';
import 'package:yomu_domain/yomu_domain.dart';

/// 本机书库的收藏集与阅读列表仓库（无需任何服务器连接，完整支持本地策展）。
final class LocalCollectionsRepository implements CollectionsRepository {
  LocalCollectionsRepository(this._db);

  final ProgressDatabase _db;
  int _idSeq = 0;

  String _nextId(String prefix) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    _idSeq = (_idSeq + 1) & 0xFFFF;
    return 'local:${prefix}_${micros}_$_idSeq';
  }

  @override
  Future<PageResult<KomgaCollection>> collections({
    int page = 0,
    int size = 20,
  }) {
    return _db.queryLocalCollections(page: page, size: size);
  }

  @override
  Future<KomgaCollection?> collectionById(String collectionId) =>
      _db.localCollectionById(collectionId);

  @override
  Future<List<KomgaCollection>> seriesCollections(String seriesId) =>
      _db.localSeriesCollections(seriesId);

  @override
  Future<KomgaCollection> createCollection({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  }) async {
    if (name.trim().isEmpty || seriesIds.isEmpty) {
      throw const BadRequestFailure();
    }
    return _db.insertLocalCollection(
      id: _nextId('col'),
      name: name,
      seriesIds: seriesIds,
      ordered: ordered,
    );
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
    if (seriesIds != null && seriesIds.isEmpty) {
      await deleteCollection(collectionId);
      return;
    }
    await _db.modifyLocalCollection(
      collectionId,
      name: name,
      ordered: ordered,
      seriesIds: seriesIds,
    );
  }

  @override
  Future<void> deleteCollection(String collectionId) =>
      _db.removeLocalCollection(collectionId);

  @override
  Future<PageResult<Series>> collectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  }) {
    return _db.queryLocalCollectionSeries(collectionId, page: page, size: size);
  }

  @override
  Future<PageResult<ReadList>> readLists({int page = 0, int size = 20}) =>
      _db.queryLocalReadLists(page: page, size: size);

  @override
  Future<ReadList?> readListById(String readListId) =>
      _db.localReadListById(readListId);

  @override
  Future<List<ReadList>> bookReadLists(String bookId) =>
      _db.localBookReadLists(bookId);

  @override
  Future<ReadList> createReadList({
    required String name,
    String summary = '',
    required List<String> bookIds,
    bool ordered = false,
  }) async {
    if (name.trim().isEmpty || bookIds.isEmpty) {
      throw const BadRequestFailure();
    }
    return _db.insertLocalReadList(
      id: _nextId('rl'),
      name: name,
      summary: summary,
      bookIds: bookIds,
      ordered: ordered,
    );
  }

  @override
  Future<void> updateReadList(
    String readListId, {
    String? name,
    String? summary,
    bool? ordered,
    List<String>? bookIds,
  }) async {
    if (bookIds != null && bookIds.isEmpty) {
      await deleteReadList(readListId);
      return;
    }
    await _db.modifyLocalReadList(
      readListId,
      name: name,
      summary: summary,
      ordered: ordered,
      bookIds: bookIds,
    );
  }

  @override
  Future<void> deleteReadList(String readListId) =>
      _db.removeLocalReadList(readListId);

  @override
  Future<PageResult<Book>> readListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  }) {
    return _db.queryLocalReadListBooks(readListId, page: page, size: size);
  }
}
