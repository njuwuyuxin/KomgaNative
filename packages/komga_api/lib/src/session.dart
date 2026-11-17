import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:komga_api/src/errors.dart';
import 'package:komga_api/src/http_cache.dart';
import 'package:komga_api/src/parsers.dart';
import 'package:komga_api/src/tls.dart';
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
  KomgaSession._(this._dio, this.address, this._cache)
    : _urls = KomgaUrls(address.baseUrl);

  final Dio _dio;
  final KomgaUrls _urls;
  final ServerAddress address;

  /// 可选的离线缓存：GET 成功写、网络类失败读（见 [HttpCache]）。
  final HttpCache? _cache;

  /// 缓存分区键。用地址而不是账号：同一服务器换账号看到的内容一样，
  /// 分开存只会白白多一份。
  String get _scope => address.baseUrl;

  /// Komga 要求 API Key 的 `comment` 在同一账号内唯一，重复时返回 400 + 该错误码。
  static const String duplicateCommentCode = 'ERR_1034';

  factory KomgaSession.withApiKey({
    required ServerAddress address,
    required String apiKey,
    Dio? dio,
    Duration timeout = const Duration(seconds: 10),
    TlsTrust? trust,
    HttpCache? cache,
  }) {
    return KomgaSession._(
      _buildDio(dio, timeout, <String, String>{'X-API-Key': apiKey}, trust),
      address,
      cache,
    );
  }

  factory KomgaSession.withBasic({
    required ServerAddress address,
    required String username,
    required String password,
    Dio? dio,
    Duration timeout = const Duration(seconds: 10),
    TlsTrust? trust,
    HttpCache? cache,
  }) {
    final token = base64Encode(utf8.encode('$username:$password'));
    return KomgaSession._(
      _buildDio(dio, timeout, <String, String>{
        'Authorization': 'Basic $token',
      }, trust),
      address,
      cache,
    );
  }

  /// 探测这个地址实际出示的证书，**不校验、不携带任何凭据**。
  ///
  /// 用途只有一个：证书被系统拒绝时，把"到底是哪张证书"摊给用户看
  /// （CN、颁发者、有效期、指纹），让他决定是否信任。
  /// 返回 null 表示没拿到证书（DNS/端口不通等，此时问题不在证书）。
  static Future<ServerCertificate?> probeCertificate({
    required ServerAddress address,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final trust = TlsTrust.probe();
    final dio = Dio()..httpClientAdapter = trust.adapter();
    dio.options
      ..connectTimeout = timeout
      ..receiveTimeout = timeout;
    try {
      await dio.getUri<Object?>(
        Uri.parse(KomgaUrls(address.baseUrl).libraries()),
        options: Options(
          headers: const <String, String>{'Accept': 'application/json'},
          // 401/404 都无所谓：握手成功就说明证书已经拿到了。
          validateStatus: (int? status) => true,
        ),
      );
    } on DioException {
      // 证书被拒（预期路径）或网络不通，都靠 [trust.presented] 判断。
    } finally {
      dio.close(force: true);
    }
    return trust.presented;
  }

  /// **不要**在这里设置 `Accept`：缩略图端点只接受 `image/jpeg`，
  /// 全局发 `application/json` 会让它返回 406（实测）。按请求分别声明。
  static Dio _buildDio(
    Dio? provided,
    Duration timeout,
    Map<String, String> headers,
    TlsTrust? trust,
  ) {
    final dio = provided ?? Dio();
    // 只有自己造的 Dio 才能换 adapter：外部注入的（测试）保留其配置。
    if (provided == null && trust != null) {
      dio.httpClientAdapter = trust.adapter();
    }
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

  /// 系列列表（分页）。`libraryId` / `search` / `sort` / `readStatus` 为空时不写入查询串。
  Future<PageResult<Series>> fetchSeries({
    int page = 0,
    int size = 20,
    String? libraryId,
    String? search,
    SeriesSort? sort,
    SeriesReadStatus? readStatus,
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

  /// 把一本书标记为未读（`DELETE /books/{id}/read-progress`，实测 204，进度被清空）。
  Future<void> markBookUnread(String bookId) =>
      _deleteVoid(_urls.bookReadProgress(bookId));

  /// 把整个系列标记为已读（`POST /series/{id}/read-progress`）。
  ///
  /// 实测：204 无 body；之后每本书 `readProgress.completed = true`、
  /// `page = 该书页数`（不是 1）。
  Future<void> markSeriesRead(String seriesId) =>
      _postVoid(_urls.seriesReadProgress(seriesId));

  /// 把整个系列标记为未读（`DELETE /series/{id}/read-progress`）。
  ///
  /// 实测：204；之后每本书的 `readProgress` 变成 null（不是 completed=false）。
  Future<void> markSeriesUnread(String seriesId) =>
      _deleteVoid(_urls.seriesReadProgress(seriesId));

  void close() => _dio.close(force: true);

  Future<Object?> _getJson(String url) async {
    try {
      final response = await _dio.get<Object?>(url, options: _jsonOptions);
      await _rememberJson(url, response.data);
      _cache?.reportOnline(_scope);
      return response.data;
    } on DioException catch (e) {
      final error = mapDioException(e);
      final cached = await _cachedJson(url, error);
      if (cached != null) return cached;
      throw error;
    }
  }

  /// 只有"连不上"或"服务端 5xx"才允许拿旧数据顶一下。
  ///
  /// 404 说明资源真的被删了，拿缓存只会让用户看到已经不存在的东西；
  /// 401/403 更不行——那是登录态问题，不是离网。
  bool _canServeStale(KomgaError error) =>
      error is KomgaNetworkError || error is KomgaServerError;

  Future<Object?> _cachedJson(String url, KomgaError error) async {
    final cache = _cache;
    if (cache == null || !_canServeStale(error)) return null;
    cache.reportOffline(_scope);
    final Uint8List? body;
    try {
      body = await cache.read(_scope, url);
    } on Object {
      return null;
    }
    if (body == null) return null;
    try {
      return jsonDecode(utf8.decode(body));
    } on FormatException {
      // 缓存坏了当没命中：宁可报"连不上"，也别把乱码当数据交给解析层。
      return null;
    }
  }

  Future<void> _rememberJson(String url, Object? data) async {
    final cache = _cache;
    if (cache == null || data == null) return;
    try {
      final body = Uint8List.fromList(utf8.encode(jsonEncode(data)));
      await cache.write(_scope, url, CacheKind.json, body);
    } on Object {
      // 写缓存失败（磁盘满/权限）只影响离线能力，不能让在线请求跟着失败。
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
      // PATCH 能成功说明网络是通的：撤掉离线提示，不必等下一次 GET。
      _cache?.reportOnline(_scope);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> _postVoid(String url) async {
    try {
      await _dio.post<Object?>(url, options: _jsonOptions);
      _cache?.reportOnline(_scope);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<void> _deleteVoid(String url) async {
    try {
      await _dio.delete<Object?>(url, options: _jsonOptions);
      _cache?.reportOnline(_scope);
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
      final bytes = _asBytes(response.data);
      if (bytes == null) {
        throw const KomgaProtocolError('服务器返回的不是图片数据');
      }
      await _rememberBytes(url, bytes);
      _cache?.reportOnline(_scope);
      return bytes;
    } on DioException catch (e) {
      final error = mapDioException(e);
      final cached = await _cachedBytes(url, error);
      if (cached != null) return cached;
      throw error;
    }
  }

  Uint8List? _asBytes(Object? data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  }

  Future<Uint8List?> _cachedBytes(String url, KomgaError error) async {
    final cache = _cache;
    if (cache == null || !_canServeStale(error)) return null;
    cache.reportOffline(_scope);
    try {
      return await cache.read(_scope, url);
    } on Object {
      return null;
    }
  }

  Future<void> _rememberBytes(String url, Uint8List bytes) async {
    final cache = _cache;
    if (cache == null) return;
    try {
      await cache.write(_scope, url, CacheKind.image, bytes);
    } on Object {
      // 同上：缓存写失败不影响本次读取。
    }
  }

  Map<Object?, Object?> _requireMap(Object? data, String what) {
    final map = asMap(data);
    if (map == null) throw KomgaProtocolError('服务器返回的$what格式不正确');
    return map;
  }
}
