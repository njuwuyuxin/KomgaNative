part of 'session.dart';

/// [KomgaSession] 的收藏集、阅读列表与阅读进度写操作扩展（ARC-12）。
extension KomgaSessionCuration on KomgaSession {
  /// 新建收藏集（SER-04）。
  Future<KomgaCollection> createCollection({
    required String name,
    required List<String> seriesIds,
    bool ordered = false,
  }) async {
    final data = _requireMap(
      await _writeJson('POST', _urls.collectionsCreate(), <String, Object?>{
        'name': name,
        'ordered': ordered,
        'seriesIds': seriesIds,
      }),
      '新建收藏集',
    );
    return collectionFromJson(data);
  }

  /// 收藏集改名（SER-04）。
  Future<void> renameCollection(String collectionId, String name) async {
    await _writeJson('PATCH', _urls.collection(collectionId), <String, Object?>{
      'name': name,
    }, expectBody: false);
  }

  /// 删除收藏集（SER-04）。
  Future<void> deleteCollection(String collectionId) async {
    await _writeJson(
      'DELETE',
      _urls.collection(collectionId),
      null,
      expectBody: false,
    );
  }

  /// 收藏集列表（UI-P3-8）。
  Future<PageResult<KomgaCollection>> fetchCollections({
    int page = 0,
    int size = 20,
  }) async {
    final data = _requireMap(
      await _getJson(_urls.collections(page: page, size: size)),
      '收藏集列表',
    );
    return pageResultFromJson(data, collectionFromJson);
  }

  /// 收藏集里的系列（有顺序）。
  Future<PageResult<Series>> fetchCollectionSeries(
    String collectionId, {
    int page = 0,
    int size = 20,
  }) async {
    final data = _requireMap(
      await _getJson(
        _urls.collectionSeries(collectionId, page: page, size: size),
      ),
      '收藏集系列',
    );
    return pageResultFromJson(data, seriesFromJson);
  }

  /// 阅读列表（UI-P3-8）。
  Future<PageResult<ReadList>> fetchReadLists({
    int page = 0,
    int size = 20,
  }) async {
    final data = _requireMap(
      await _getJson(_urls.readLists(page: page, size: size)),
      '阅读列表',
    );
    return pageResultFromJson(data, readListFromJson);
  }

  /// 阅读列表里的书（有顺序）。
  Future<PageResult<Book>> fetchReadListBooks(
    String readListId, {
    int page = 0,
    int size = 20,
  }) async {
    final data = _requireMap(
      await _getJson(_urls.readListBooks(readListId, page: page, size: size)),
      '阅读列表书籍',
    );
    return pageResultFromJson(data, bookFromJson);
  }

  /// 更新阅读进度（`PATCH /api/v1/books/{id}/read-progress`，页码 1 基）。
  Future<void> updateReadProgress(
    String bookId, {
    int? page,
    bool? completed,
  }) async {
    final body = <String, Object>{
      if (page != null) 'page': page,
      if (completed != null) 'completed': completed,
    };
    if (body.isEmpty) return;
    await _patchJson(_urls.bookReadProgress(bookId), body);
  }

  /// 把一本书标记为未读（`DELETE /books/{id}/read-progress`）。
  Future<void> markBookUnread(String bookId) =>
      _deleteVoid(_urls.bookReadProgress(bookId));

  /// 把整个系列标记为已读（`POST /series/{id}/read-progress`）。
  Future<void> markSeriesRead(String seriesId) =>
      _postVoid(_urls.seriesReadProgress(seriesId));

  /// 把整个系列标记为未读（`DELETE /series/{id}/read-progress`）。
  Future<void> markSeriesUnread(String seriesId) =>
      _deleteVoid(_urls.seriesReadProgress(seriesId));
}
