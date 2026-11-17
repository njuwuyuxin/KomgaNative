/// Komga URL 构造。
///
/// 参数细节来自官方 OpenAPI 1.30.1 实测：
/// - 页图只支持 `convert=jpeg|png`，**没有 resize 参数**（降采样必须在客户端做）；
/// - 页码默认 1 基（`zero_based=false`）。
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

  String series({
    int page = 0,
    int size = 20,
    String? libraryId,
    String? search,
  }) {
    final q = <String, String>{
      'page': '$page',
      'size': '$size',
      if (libraryId != null) 'library_id': libraryId,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    return _withQuery('$_base/api/v1/series', q);
  }

  String seriesBooks(String seriesId, {int page = 0, int size = 100}) =>
      _withQuery('$_base/api/v1/series/$seriesId/books', {
        'page': '$page',
        'size': '$size',
      });

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
