import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:komga_api/src/errors.dart';
import 'package:komga_domain/komga_domain.dart';

/// 一次服务器会话。
///
/// 设计：**两种鉴权方式共用一个类**。
/// - [KomgaSession.withBasic] 只在"首次登录、换取 API Key"时使用；
/// - [KomgaSession.withApiKey] 是常态（无 cookie、多服务器互不干扰）。
///
/// M1 只暴露连接流程需要的三个调用；书架/系列/阅读接口在后续切片加。
class KomgaSession {
  KomgaSession._(this._dio, this.address);

  final Dio _dio;
  final ServerAddress address;

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

  static Dio _buildDio(
    Dio? provided,
    Duration timeout,
    Map<String, String> headers,
  ) {
    final dio = provided ?? Dio();
    dio.options
      ..connectTimeout = timeout
      ..receiveTimeout = timeout
      ..headers = <String, String>{...headers, 'Accept': 'application/json'};
    return dio;
  }

  String _url(String path) => '${address.baseUrl}$path';

  /// 校验凭据是否有效，并返回该账号可见的库。
  Future<List<Library>> fetchLibraries() async {
    final Object? data = await _get(_url('/api/v1/libraries'));
    if (data is! List) {
      throw const KomgaProtocolError('服务器返回的库列表格式不正确');
    }
    return data
        .whereType<Map<String, Object?>>()
        .map(_libraryFromJson)
        .toList(growable: false);
  }

  /// 当前账号信息（用于确认 API Key 可用、展示用户名）。
  Future<Account> fetchAccount() async {
    final Object? data = await _get(_url('/api/v2/users/me'));
    if (data is! Map<String, Object?>) {
      throw const KomgaProtocolError('服务器返回的账号信息格式不正确');
    }
    return Account(
      id: (data['id'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      roles:
          (data['roles'] as List<Object?>?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
    );
  }

  /// 自助创建一把 API Key（需要 Basic 会话）。
  ///
  /// Komga 只接受 `{comment}`，返回 `ApiKeyDto.key`。客户端的做法是：用密码换一次 Key，
  /// 之后只保存 Key，不再保存密码。
  Future<String> createApiKey({required String comment}) async {
    final Object? data = await _post(
      _url('/api/v2/users/me/api-keys'),
      <String, Object>{'comment': comment},
    );
    if (data is! Map<String, Object?>) {
      throw const KomgaProtocolError('服务器返回的 API Key 格式不正确');
    }
    final key = data['key'];
    if (key is! String || key.isEmpty) {
      throw const KomgaProtocolError('服务器没有返回 API Key');
    }
    return key;
  }

  Future<Object?> _get(String url) async {
    try {
      final response = await _dio.get<Object?>(url);
      return response.data;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  Future<Object?> _post(String url, Map<String, Object> body) async {
    try {
      final response = await _dio.post<Object?>(url, data: body);
      return response.data;
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  void close() => _dio.close(force: true);

  static Library _libraryFromJson(Map<String, Object?> json) => Library(
    id: (json['id'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    unavailable: json['unavailable'] == true,
  );
}
