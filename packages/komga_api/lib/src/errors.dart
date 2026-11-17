import 'dart:convert';

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

/// 400：服务端拒绝了这次请求（参数越界、唯一约束冲突等）。
///
/// [serverCode] 是 Komga 的机器可读错误码。实测 `message: "ERR_1034"` 表示
/// "API Key 的 comment 在该账号下已存在"——人类可读文案缺失，只能靠这个码判断。
/// 注意：400 的 body **可能完全为空**（如 `read-progress` 传 `page=0`），
/// 所以 [message] 一定有值，不能依赖 body。
class KomgaBadRequestError extends KomgaError {
  const KomgaBadRequestError(
    super.message, {
    super.statusCode,
    super.cause,
    this.serverCode,
  });

  final String? serverCode;
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
      final serverCode = _serverCode(e.response?.data);
      final detail = _serverMessage(e.response?.data);
      final suffix = detail == null ? '' : '：$detail';
      if (status == 401 || status == 403) {
        return KomgaAuthError('认证失败（$status）', statusCode: status, cause: e);
      }
      if (status == 404) return KomgaNotFoundError('资源不存在（404）', cause: e);
      if (status == 400) {
        return KomgaBadRequestError(
          '服务端拒绝了请求（400）$suffix',
          statusCode: 400,
          serverCode: serverCode,
          cause: e,
        );
      }
      if (status == 406) {
        // 实测：缩略图端点只接受 `Accept: image/jpeg`，否则 406。
        return KomgaProtocolError(
          '服务端不接受期望的响应类型（406）$suffix',
          statusCode: 406,
          cause: e,
        );
      }
      if (status >= 500) {
        return KomgaServerError(
          '服务端错误（$status）$suffix',
          statusCode: status,
          cause: e,
        );
      }
      return KomgaProtocolError(
        '意外的响应（$status）$suffix',
        statusCode: status,
        cause: e,
      );
    case DioExceptionType.unknown:
      return KomgaProtocolError('请求异常：${e.message}', cause: e);
  }
}

/// Komga 的错误体有多种形态，都要容忍：
/// - Spring 默认错误页：`{"timestamp":…,"status":400,"error":"Bad Request","message":"…","path":"…"}`
/// - 校验失败：`{"violations":[{"field":"…","message":"…"}]}`
/// - 机器码：`{"message":"ERR_1034"}`
/// - **空 body**（实测 `page=0` 的 400）
Map<Object?, Object?>? _asJsonMap(Object? data) {
  if (data is Map<Object?, Object?>) return data;
  if (data is String && data.trim().startsWith('{')) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map<Object?, Object?>) return decoded;
    } on FormatException {
      return null;
    }
  }
  return null;
}

final RegExp _codePattern = RegExp(r'^ERR_\d+$');

String? _serverCode(Object? data) {
  final message = _asJsonMap(data)?['message'];
  if (message is String && _codePattern.hasMatch(message)) return message;
  return null;
}

String? _serverMessage(Object? data) {
  final map = _asJsonMap(data);
  if (map == null) return null;
  final message = map['message'];
  if (message is String &&
      message.isNotEmpty &&
      !_codePattern.hasMatch(message)) {
    return message;
  }
  final violations = map['violations'];
  if (violations is List<Object?>) {
    for (final violation in violations) {
      if (violation is! Map<Object?, Object?>) continue;
      final text = violation['message'];
      if (text is String && text.isNotEmpty) return text;
    }
  }
  return null;
}
