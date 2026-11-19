import 'package:komga_domain/komga_domain.dart';

/// Komga URL 构造。
///
/// 参数细节已对**真实 Komga 1.30.1 实例**逐条实测，证据与复现步骤见
/// `docs/komga-api-verification.md`，并由 `test/contract_test.dart` 对着
/// `test/fixtures/openapi-1.30.1.json` 做机器校验。要点：
/// - 页图只支持 `convert=jpeg|png`，**`width`/`height`/`scale` 会被静默忽略**
///   （三种参数返回的字节 SHA 完全相同），降采样必须在客户端做；
/// - 页码 1 基：`zero_based=false` 时 `pages/1` 是首页，`pages/0` 返回 400。
class KomgaUrls {
  KomgaUrls(String baseUrl) : _base = _normalize(baseUrl);

  final String _base;

  static String _normalize(String baseUrl) {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  String get base => _base;

  String libraries() => '$_base/api/v1/libraries';

  /// 当前用户（API Key 的归属者）。
  String me() => '$_base/api/v2/users/me';

  /// 系列列表。`sort` / `readStatus` 为空时不写入查询串（用服务端默认）。
  ///
  /// 取值已对真实 Komga 1.30.1 验证，见 `docs/series-queries.md`。
  String series({
    int page = 0,
    int size = 20,
    String? libraryId,
    String? search,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
  }) {
    final q = <String, String>{
      'page': '$page',
      'size': '$size',
      if (libraryId != null) 'library_id': libraryId,
      if (search != null && search.isNotEmpty) 'search': search,
      if (sort != null) 'sort': sortWireValue(sort),
      if (readStatus != null) 'read_status': readStatusWireValue(readStatus),
    };
    return _withQuery('$_base/api/v1/series', q);
  }

  String seriesBooks(String seriesId, {int page = 0, int size = 100}) =>
      _withQuery('$_base/api/v1/series/$seriesId/books', {
        'page': '$page',
        'size': '$size',
      });

  /// 收藏集列表（`GET /api/v1/collections`）。
  String collections({int page = 0, int size = 20}) => _withQuery(
    '$_base/api/v1/collections',
    {'page': '$page', 'size': '$size'},
  );

  /// 收藏集里的系列（`GET /api/v1/collections/{id}/series`）。
  String collectionSeries(String collectionId, {int page = 0, int size = 20}) =>
      _withQuery('$_base/api/v1/collections/$collectionId/series', {
        'page': '$page',
        'size': '$size',
      });

  /// 阅读列表（`GET /api/v1/readlists`）。
  String readLists({int page = 0, int size = 20}) =>
      _withQuery('$_base/api/v1/readlists', {'page': '$page', 'size': '$size'});

  /// 阅读列表里的书（`GET /api/v1/readlists/{id}/books`）。
  String readListBooks(String readListId, {int page = 0, int size = 20}) =>
      _withQuery('$_base/api/v1/readlists/$readListId/books', {
        'page': '$page',
        'size': '$size',
      });

  /// 单个系列（`GET /api/v1/series/{seriesId}`）。
  String seriesById(String seriesId) => '$_base/api/v1/series/$seriesId';

  String book(String bookId) => '$_base/api/v1/books/$bookId';

  String bookPages(String bookId) => '$_base/api/v1/books/$bookId/pages';

  /// 单页图片。
  ///
  /// [convertToJpeg] 用于大体积 PNG：JPEG 解码期可低成本降采样，代价是服务端 CPU。
  String pageImage(String bookId, int page, {bool convertToJpeg = false}) {
    final q = <String, String>{
      'zero_based': 'false',
      if (convertToJpeg) 'convert': 'jpeg',
    };
    return _withQuery('$_base/api/v1/books/$bookId/pages/$page', q);
  }

  String bookThumbnail(String bookId) =>
      '$_base/api/v1/books/$bookId/thumbnail';

  String seriesThumbnail(String seriesId) =>
      '$_base/api/v1/series/$seriesId/thumbnail';

  String bookReadProgress(String bookId) =>
      '$_base/api/v1/books/$bookId/read-progress';

  /// 系列级进度：`POST` = 全部标记已读，`DELETE` = 全部标记未读（实测 204）。
  String seriesReadProgress(String seriesId) =>
      '$_base/api/v1/series/$seriesId/read-progress';

  String ondeck({int size = 20}) =>
      _withQuery('$_base/api/v1/books/ondeck', {'size': '$size'});

  String apiKeys() => '$_base/api/v2/users/me/api-keys';

  static String _withQuery(String url, Map<String, String> query) {
    if (query.isEmpty) return url;
    final encoded = query.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return '$url?$encoded';
  }
}

/// `SeriesSort` → Komga `sort` 参数值。
///
/// 全部对真实 Komga 1.30.1 验证过（`docs/series-queries.md`）：
/// `metadata.titleSort,{asc,desc}`、`createdDate,desc`、`readProgress.lastModified,desc`。
String sortWireValue(SeriesSort sort) => switch (sort) {
  SeriesSort.titleAsc => 'metadata.titleSort,asc',
  SeriesSort.titleDesc => 'metadata.titleSort,desc',
  SeriesSort.recentlyAdded => 'createdDate,desc',
  SeriesSort.recentlyRead => 'readProgress.lastModified,desc',
  // 2026-11-19 对真实 Komga 1.30.1 验证，见 docs/series-queries.md。
  SeriesSort.booksCountDesc => 'booksCount,desc',
  SeriesSort.releaseDateDesc => 'booksMetadata.releaseDate,desc',
};

/// `SeriesReadStatus` → Komga `read_status` 参数值。
String readStatusWireValue(SeriesReadStatus status) => switch (status) {
  SeriesReadStatus.unread => 'UNREAD',
  SeriesReadStatus.inProgress => 'IN_PROGRESS',
  SeriesReadStatus.read => 'READ',
};
