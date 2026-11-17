import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:komga_api/src/errors.dart';
import 'package:komga_api/src/parsers.dart';
import 'package:komga_api/src/urls.dart';
import 'package:komga_domain/komga_domain.dart';

/// 一次服务器会话。
///
/// 设计：**两种鉴权方式共用一个类**。
/// - [KomgaSession.withBasic] 只在"首次登录、换取 API Key"时使用；
/// - [KomgaSession.withApiKey] 是常态（无 cookie、多服务器互不干扰）。
///
/// 端点与参数已对真实 Komga 1.30.1 实例验证，见 `docs/komga-api-verification.md`。
class KomgaSession {
  KomgaSession._(this._dio, this.address) : _urls = KomgaUrls(address.baseUrl);

  final Dio _dio;
  final KomgaUrls _urls;
  final ServerAddress address;

  /// Komga 要求 API Key 的 `comment` 在同一账号内唯一，重复时返回 400 + 该错误码。
  static const String duplicateCommentCode = 'ERR_1034';

  factory KomgaSession.withApiKey({
    required ServerAddress address,
    required String apiKey,
    Dio? dio,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return KomgaSession._(
      _buildDio(dio, timeout, <String, String>{'X-API-Key': apiKey}),
      address,
    );
  }

  factory KomgaSession.withBasic({
    required ServerAddress address,
    required String username,
    required String password,
    Dio? dio,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final token = base64Encode(utf8.encode('$username:$password'));
    return KomgaSession._(
      _buildDio(dio, timeout, <String, String>{
        'Authorization': 'Basic $token',
      }),
      address,
    );
  }

  /// **不要**在这里设置 `Accept`：缩略图端点只接受 `image/jpeg`，
  /// 全局发 `application/json` 会让它返回 406（实测）。按请求分别声明。
  static Dio _buildDio(
    Dio? provided,
    Duration timeout,
    Map<String, String> headers,
  ) {
    final dio = provided ?? Dio();
    dio.options
      ..connectTimeout = timeout
      ..receiveTimeout = timeout
      ..headers = <String, String>{...headers};
    return dio;
  }

  Options get _jsonOptions =>
      Options(headers: const <String, String>{'Accept': 'application/json'});

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

  /// 系列列表（分页）。`libraryId` / `search` 为空时不写入查询串。
  Future<PageResult<Series>> fetchSeries({
    int page = 0,
    int size = 20,
    String? libraryId,
    String? search,
  }) async {
    final data = _requireMap(
      await _getJson(
        _urls.series(
          page: page,
          size: size,
          libraryId: libraryId,
          search: search,
        ),
      ),
      '系列列表',
    );
    return pageResultFromJson(data, seriesFromJson);
  }

  Future<PageResult<Book>> fetchSeriesBooks(
    String seriesId, {
    int page = 0,
    int size = 100,
  }) async {
    final data = _requireMap(
      await _getJson(_urls.seriesBooks(seriesId, page: page, size: size)),
      '书籍列表',
    );
    return pageResultFromJson(data, bookFromJson);
  }

  /// 单个系列。系列已被删除时返回 `null`（调用方据此提示，而不是报错）。
  Future<Series?> fetchSeriesById(String seriesId) async {
    try {
      final data = _requireMap(
        await _getJson(_urls.seriesById(seriesId)),
        '系列信息',
      );
      return seriesFromJson(data);
    } on KomgaNotFoundError {
      return null;
    }
  }

  Future<Book> fetchBook(String bookId) async {
    final data = _requireMap(await _getJson(_urls.book(bookId)), '书籍信息');
    return bookFromJson(data);
  }

  /// "继续阅读"列表（Komga 的 ondeck：在读过但还没读完的书）。
  Future<PageResult<Book>> fetchOndeck({int size = 20}) async {
    final data = _requireMap(
      await _getJson(_urls.ondeck(size: size)),
      '继续阅读列表',
    );
    return pageResultFromJson(data, bookFromJson);
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

  /// 页图原始字节。页码 **1 基**（与 `/pages` 返回的 `number` 一致）。
  Future<Uint8List> fetchPageImage(
    String bookId,
    int page, {
    bool convertToJpeg = false,
  }) => _getBytes(_urls.pageImage(bookId, page, convertToJpeg: convertToJpeg));

  /// 缩略图：**只接受 `image/jpeg`**（实测 `Accept: application/json` → 406）。
  Future<Uint8List> fetchSeriesThumbnail(String seriesId) =>
      _getBytes(_urls.seriesThumbnail(seriesId));

  Future<Uint8List> fetchBookThumbnail(String bookId) =>
      _getBytes(_urls.bookThumbnail(bookId));

  /// 自助创建一把 API Key（需要 Basic 会话）。
  ///
  /// Komga 只接受 `{comment}`，返回 `ApiKeyDto.key`。客户端的做法是：用密码换一次 Key，
  /// 之后只保存 Key，不再保存密码。
  ///
  /// 实测：`comment` 在同一账号下**必须唯一**，重复会 400 + `ERR_1034`。
  /// 于是"注销后重新登录"必然撞车，这里撞上就换一个带时间戳的 comment 重试一次。
  Future<String> createApiKey({required String comment}) async {
    try {
      return await _createApiKey(comment);
    } on KomgaBadRequestError catch (error) {
      if (error.serverCode != duplicateCommentCode) rethrow;
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

  /// 更新阅读进度（`PATCH /api/v1/books/{id}/read-progress`）。
  ///
  /// 两个字段都是可选的局部更新（实测）：只发 `completed` 时页码保持不变。
  /// **页码 1 基**；`page=0` 会被服务端 400 拒绝（且 body 为空）。
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

  void close() => _dio.close(force: true);

  Future<Object?> _getJson(String url) async {
    try {
      final response = await _dio.get<Object?>(url, options: _jsonOptions);
      return response.data;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<Object?> _postJson(String url, Map<String, Object> body) async {
    try {
      final response = await _dio.post<Object?>(
        url,
        data: body,
        options: _jsonOptions,
      );
      return response.data;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> _patchJson(String url, Map<String, Object> body) async {
    try {
      // 204 No Content：不要读 data。
      await _dio.patch<Object?>(url, data: body, options: _jsonOptions);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<Uint8List> _getBytes(String url) async {
    try {
      final response = await _dio.get<Object?>(
        url,
        options: Options(
          headers: const <String, String>{'Accept': 'image/*,image/jpeg'},
          responseType: ResponseType.bytes,
        ),
      );
      final data = response.data;
      if (data is Uint8List) return data;
      if (data is List<int>) return Uint8List.fromList(data);
      throw const KomgaProtocolError('服务器返回的不是图片数据');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Map<Object?, Object?> _requireMap(Object? data, String what) {
    final map = asMap(data);
    if (map == null) throw KomgaProtocolError('服务器返回的$what格式不正确');
    return map;
  }
}
