import 'package:dio/dio.dart';

/// 统一的错误模型：UI 只 switch 这个类型，不接触 `DioException`。
sealed class KomgaError implements Exception {
  const KomgaError(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => '$runtimeType($statusCode): $message';
}

/// 网络不可达 / DNS / 超时。
class KomgaNetworkError extends KomgaError {
  const KomgaNetworkError(super.message, {super.cause});
}

/// 401/403：API Key 失效或权限不足。需要重新登录，**不要**重试。
class KomgaAuthError extends KomgaError {
  const KomgaAuthError(super.message, {super.statusCode, super.cause});
}

/// 404：书/系列已被删除，调用方应清理本地缓存。
class KomgaNotFoundError extends KomgaError {
  const KomgaNotFoundError(super.message, {super.cause})
    : super(statusCode: 404);
}

/// 5xx：可退避重试。
class KomgaServerError extends KomgaError {
  const KomgaServerError(super.message, {super.statusCode, super.cause});
}

/// 响应无法解析（服务端版本不兼容/反代返回了 HTML 等）。
class KomgaProtocolError extends KomgaError {
  const KomgaProtocolError(super.message, {super.statusCode, super.cause});
}

/// 请求被主动取消（快速翻页时正常发生，不应提示用户）。
class KomgaCancelledError extends KomgaError {
  const KomgaCancelledError() : super('请求已取消');
}

/// 把 dio 的异常折叠成领域错误。
KomgaError mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.cancel:
      return const KomgaCancelledError();
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return KomgaNetworkError('无法连接服务器：${e.message ?? e.type.name}', cause: e);
    case DioExceptionType.badResponse:
      final status = e.response?.statusCode ?? 0;
      final message = '服务端返回 $status';
      if (status == 401 || status == 403) {
        return KomgaAuthError(message, statusCode: status, cause: e);
      }
      if (status == 404) return KomgaNotFoundError(message, cause: e);
      if (status >= 500)
        return KomgaServerError(message, statusCode: status, cause: e);
      return KomgaProtocolError(message, statusCode: status, cause: e);
    case DioExceptionType.unknown:
      return KomgaProtocolError('请求异常：${e.message}', cause: e);
  }
}
