part of 'session.dart';

/// [KomgaSession] 的目录、搜索、页图与账号管理能力扩展（ARC-12）。
extension KomgaSessionCatalog on KomgaSession {
  /// 校验凭据是否有效，并返回该账号可见的库。
  Future<List<Library>> fetchLibraries() async {
    final data = await _getJson(_urls.libraries());
    if (data is! List<Object?>) {
      throw const KomgaProtocolError('服务器返回的库列表格式不正确');
    }
    return data
        .whereType<Map<Object?, Object?>>()
        .map(libraryFromJson)
        .toList(growable: false);
  }

  /// 当前账号信息（用于确认 API Key 可用、展示用户名）。
  Future<Account> fetchAccount() async {
    final data = _requireMap(await _getJson(_urls.me()), '账号信息');
    return accountFromJson(data);
  }

  /// 系列列表（分页）。
  Future<PageResult<Series>> fetchSeries({
    int page = 0,
    int size = 20,
    String? libraryId,
    String? search,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
    String? tag,
  }) async {
    final data = _requireMap(
      await _getJson(
        _urls.series(
          page: page,
          size: size,
          libraryId: libraryId,
          search: search,
          sort: sort,
          readStatus: readStatus,
          tag: tag,
        ),
      ),
      '系列列表',
    );
    return pageResultFromJson(
      data,
      (Map<Object?, Object?> m) => seriesFromJson(m).withSource(_scope),
    );
  }

  Future<PageResult<Book>> fetchSeriesBooks(
    String seriesId, {
    int page = 0,
    int size = 100,
    BooksSort? sort,
    SeriesReadStatus? readStatus,
  }) async {
    final data = _requireMap(
      await _getJson(
        _urls.seriesBooks(
          seriesId,
          page: page,
          size: size,
          sort: sort,
          readStatus: readStatus,
        ),
      ),
      '书籍列表',
    );
    return pageResultFromJson(
      data,
      (Map<Object?, Object?> m) => bookFromJson(m).withSource(_scope),
    );
  }

  /// 单个系列。系列已被删除时返回 `null`。
  Future<Series?> fetchSeriesById(String seriesId) async {
    try {
      final data = _requireMap(
        await _getJson(_urls.seriesById(seriesId)),
        '系列信息',
      );
      return seriesFromJson(data).withSource(_scope);
    } on KomgaNotFoundError {
      return null;
    }
  }

  Future<Book> fetchBook(String bookId) async {
    final data = _requireMap(await _getJson(_urls.book(bookId)), '书籍信息');
    return bookFromJson(data).withSource(_scope);
  }

  /// 全局书搜索。
  Future<PageResult<Book>> searchBooks(
    String query, {
    int page = 0,
    int size = 20,
  }) async {
    final data = _requireMap(
      await _getJson(_urls.books(page: page, size: size, search: query)),
      '书籍搜索',
    );
    return pageResultFromJson(
      data,
      (Map<Object?, Object?> m) => bookFromJson(m).withSource(_scope),
    );
  }

  /// 在读中的书（Komga 的 Keep Reading：按最近阅读时间倒序）。
  Future<PageResult<Book>> fetchInProgressBooks({
    int page = 0,
    int size = 20,
  }) async {
    final data = _requireMap(
      await _getJson(_urls.inProgressBooks(page: page, size: size)),
      '在读书籍列表',
    );
    return pageResultFromJson(
      data,
      (Map<Object?, Object?> m) => bookFromJson(m).withSource(_scope),
    );
  }

  /// 待读下一本列表（Komga 的 ondeck：已读过至少一本且当前无在读书的系列的首本未读）。
  Future<PageResult<Book>> fetchOndeck({int size = 20}) async {
    final data = _requireMap(
      await _getJson(_urls.ondeck(size: size)),
      '继续阅读列表',
    );
    return pageResultFromJson(
      data,
      (Map<Object?, Object?> m) => bookFromJson(m).withSource(_scope),
    );
  }

  Future<List<PageInfo>> fetchBookPages(String bookId) async {
    final data = await _getJson(_urls.bookPages(bookId));
    if (data is! List<Object?>) {
      throw const KomgaProtocolError('服务器返回的页面列表格式不正确');
    }
    return data
        .whereType<Map<Object?, Object?>>()
        .map(pageInfoFromJson)
        .toList(growable: false);
  }

  /// 页图原始字节。页码 **1 基**。
  Future<Uint8List> fetchPageImage(
    String bookId,
    int page, {
    bool convertToJpeg = false,
  }) => _getBytes(_urls.pageImage(bookId, page, convertToJpeg: convertToJpeg));

  /// 单页低精度缩略图（长边 300px JPEG，页码 **1 基**）。
  Future<Uint8List> fetchPageThumbnail(String bookId, int page) => _getBytes(
    _urls.pageThumbnail(bookId, page),
    priority: RequestPriority.decorative,
  );

  /// 缩略图：**只接受 `image/jpeg`**（实测 `Accept: application/json` → 406）。
  Future<Uint8List> fetchSeriesThumbnail(String seriesId) => _getBytes(
    _urls.seriesThumbnail(seriesId),
    priority: RequestPriority.decorative,
  );

  Future<Uint8List> fetchBookThumbnail(String bookId) => _getBytes(
    _urls.bookThumbnail(bookId),
    priority: RequestPriority.decorative,
  );

  /// 自助创建一把 API Key（需要 Basic 会话）。
  Future<String> createApiKey({required String comment}) async {
    try {
      return await _createApiKey(comment);
    } on KomgaBadRequestError catch (error) {
      if (error.serverCode != KomgaSession.duplicateCommentCode) rethrow;
      final unique = '$comment ${DateTime.now().toUtc().toIso8601String()}';
      return _createApiKey(unique);
    }
  }

  Future<String> _createApiKey(String comment) async {
    final data = _requireMap(
      await _postJson(_urls.apiKeys(), <String, Object>{'comment': comment}),
      'API Key',
    );
    final key = data['key'];
    if (key is! String || key.isEmpty) {
      throw const KomgaProtocolError('服务器没有返回 API Key');
    }
    return key;
  }
}
