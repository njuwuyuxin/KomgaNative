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

  /// 收藏集详情（`GET /api/v1/collections/{id}`）。
  Future<KomgaCollection> fetchCollection(String collectionId) async {
    final data = _requireMap(
      await _getJson(_urls.collection(collectionId)),
      '收藏集',
    );
    return collectionFromJson(data);
  }

  /// 系列所属的收藏集（`GET /api/v1/series/{seriesId}/collections`，实测返回裸数组）。
  Future<List<KomgaCollection>> fetchSeriesCollections(String seriesId) async {
    final data = await _getJson(_urls.seriesCollections(seriesId));
    if (data is! List<Object?>) {
      throw const KomgaProtocolError('服务器返回的系列收藏集不是数组');
    }
    return data
        .map(asMap)
        .whereType<Map<Object?, Object?>>()
        .map(collectionFromJson)
        .toList(growable: false);
  }

  /// 更新收藏集（`PATCH /api/v1/collections/{id}`）：支持改名、改排序、更新 `seriesIds`。
  ///
  /// 实测 Komga 1.30.1：`seriesIds` 为空数组时服务端返回 400（空 body），
  /// 清空收藏集必须走 [deleteCollection]。
  Future<void> updateCollection(
    String collectionId, {
    String? name,
    bool? ordered,
    List<String>? seriesIds,
  }) async {
    final body = <String, Object?>{
      if (name != null) 'name': name,
      if (ordered != null) 'ordered': ordered,
      if (seriesIds != null) 'seriesIds': seriesIds,
    };
    if (body.isEmpty) return;
    await _writeJson(
      'PATCH',
      _urls.collection(collectionId),
      body,
      expectBody: false,
    );
  }

  /// 收藏集改名（SER-04）。
  Future<void> renameCollection(String collectionId, String name) =>
      updateCollection(collectionId, name: name);

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

  /// 阅读列表详情（`GET /api/v1/readlists/{id}`）。
  Future<ReadList> fetchReadList(String readListId) async {
    final data = _requireMap(
      await _getJson(_urls.readList(readListId)),
      '阅读列表',
    );
    return readListFromJson(data);
  }

  /// 单本书所属的阅读列表（`GET /api/v1/books/{bookId}/readlists`，实测返回裸数组）。
  Future<List<ReadList>> fetchBookReadLists(String bookId) async {
    final data = await _getJson(_urls.bookReadLists(bookId));
    if (data is! List<Object?>) {
      throw const KomgaProtocolError('服务器返回的书籍阅读列表不是数组');
    }
    return data
        .map(asMap)
        .whereType<Map<Object?, Object?>>()
        .map(readListFromJson)
        .toList(growable: false);
  }

  /// 新建阅读列表（`POST /api/v1/readlists`）。
  ///
  /// 实测 Komga 1.30.1：`bookIds` 不能为空（空列表返回 400 空 body）。
  Future<ReadList> createReadList({
    required String name,
    String summary = '',
    required List<String> bookIds,
    bool ordered = false,
  }) async {
    final data = _requireMap(
      await _writeJson('POST', _urls.readListsCreate(), <String, Object?>{
        'name': name,
        'summary': summary,
        'ordered': ordered,
        'bookIds': bookIds,
      }),
      '新建阅读列表',
    );
    return readListFromJson(data);
  }

  /// 更新阅读列表（`PATCH /api/v1/readlists/{id}`）：支持改名、改简介、改排序、更新 `bookIds`。
  ///
  /// 实测 Komga 1.30.1：`bookIds` 为空数组时服务端返回 400（空 body），
  /// 清空阅读列表必须走 [deleteReadList]。
  Future<void> updateReadList(
    String readListId, {
    String? name,
    String? summary,
    bool? ordered,
    List<String>? bookIds,
  }) async {
    final body = <String, Object?>{
      if (name != null) 'name': name,
      if (summary != null) 'summary': summary,
      if (ordered != null) 'ordered': ordered,
      if (bookIds != null) 'bookIds': bookIds,
    };
    if (body.isEmpty) return;
    await _writeJson(
      'PATCH',
      _urls.readList(readListId),
      body,
      expectBody: false,
    );
  }

  /// 删除阅读列表（`DELETE /api/v1/readlists/{id}`）。
  Future<void> deleteReadList(String readListId) async {
    await _writeJson(
      'DELETE',
      _urls.readList(readListId),
      null,
      expectBody: false,
    );
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
