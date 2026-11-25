import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:komga_api/src/errors.dart';
import 'package:komga_api/src/http_cache.dart';
import 'package:komga_api/src/parsers.dart';
import 'package:komga_api/src/tls.dart';
import 'package:komga_api/src/urls.dart';
import 'package:komga_domain/komga_domain.dart';

part 'session_catalog.dart';
part 'session_curation.dart';

/// 一次服务器会话核心（传输、鉴权、证书探测与离线缓存回退）。
///
/// 目录查询见 `session_catalog.dart`，收藏集与进度写操作见 `session_curation.dart`。
class KomgaSession {
  KomgaSession._(this._dio, this.address, this._cache)
    : _urls = KomgaUrls(address.baseUrl);

  final Dio _dio;
  final KomgaUrls _urls;
  final ServerAddress address;
  final HttpCache? _cache;

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

  static Dio _buildDio(
    Dio? provided,
    Duration timeout,
    Map<String, String> headers,
    TlsTrust? trust,
  ) {
    final dio = provided ?? Dio();
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
      // 写缓存失败不影响在线请求。
    }
  }

  Future<Object?> _writeJson(
    String method,
    String url,
    Object? body, {
    bool expectBody = true,
  }) async {
    try {
      final response = await _dio.request<Object?>(
        url,
        data: body,
        options: _jsonOptions.copyWith(method: method),
      );
      _cache?.reportOnline(_scope);
      if (!expectBody) return null;
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
      await _dio.patch<Object?>(url, data: body, options: _jsonOptions);
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

  Future<Uint8List> _getBytes(
    String url, {
    RequestPriority priority = RequestPriority.primary,
  }) async {
    // 整本下载受保护的页图直接命中本地缓存（Cache-First），在线阅读零重复流量。
    final pinned = await _pinnedBytes(url);
    if (pinned != null) return pinned;
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
      _cache?.reportOnline(_scope, priority: priority);
      return bytes;
    } on DioException catch (e) {
      final error = mapDioException(e);
      final cached = await _cachedBytes(url, error, priority: priority);
      if (cached != null) return cached;
      throw error;
    }
  }

  Future<Uint8List?> _pinnedBytes(String url) async {
    final cache = _cache;
    if (cache == null) return null;
    try {
      return await cache.readPinned(_scope, url);
    } on Object {
      return null;
    }
  }

  Uint8List? _asBytes(Object? data) {
    if (data is Uint8List) return data;
    if (data is List<int>) return Uint8List.fromList(data);
    return null;
  }

  Future<Uint8List?> _cachedBytes(
    String url,
    KomgaError error, {
    RequestPriority priority = RequestPriority.primary,
  }) async {
    final cache = _cache;
    if (cache == null || !_canServeStale(error)) return null;
    cache.reportOffline(_scope, priority: priority);
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
      // 缓存写失败不影响本次读取。
    }
  }

  Map<Object?, Object?> _requireMap(Object? data, String what) {
    final map = asMap(data);
    if (map == null) throw KomgaProtocolError('服务器返回的$what格式不正确');
    return map;
  }
}
