import 'package:dio/dio.dart';
import 'package:komga_api/src/errors.dart';
import 'package:komga_api/src/urls.dart';

/// Komga HTTP 传输层。
///
/// 约定：
/// - 一律带 `X-API-Key`（不用 cookie session，避免多服务器共享 cookie）；
/// - 每次请求可传 [CancelToken]，快速翻页时要取消过期请求；
/// - 所有异常折叠成 [KomgaError]，UI 层不需要认识 dio。
class KomgaTransport {
  KomgaTransport({required String baseUrl, required String apiKey, Dio? dio})
    : urls = KomgaUrls(baseUrl),
      _apiKey = apiKey,
      _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 8)
      ..receiveTimeout = const Duration(seconds: 20)
      ..headers = <String, String>{
        'X-API-Key': _apiKey,
        'Accept': 'application/json',
      };
  }

  final KomgaUrls urls;
  final Dio _dio;
  final String _apiKey;

  Dio get raw => _dio;

  /// GET JSON。返回原始 Map/List，DTO 映射由 M1 的生成层负责。
  Future<T> getJson<T>(
    String url, {
    CancelToken? cancelToken,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        url,
        cancelToken: cancelToken,
        queryParameters: query,
      );
      final data = response.data;
      if (data is T) return data;
      throw KomgaProtocolError('响应类型不符：期望 $T，实际 ${data.runtimeType}');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// PATCH 进度。服务端返回 204，无 body。
  Future<void> patchReadProgress(
    String bookId, {
    required int page,
    required bool completed,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.patch<void>(
        urls.bookReadProgress(bookId),
        data: <String, Object>{'page': page, 'completed': completed},
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  void close() => _dio.close(force: true);
}
