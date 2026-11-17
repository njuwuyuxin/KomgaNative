import 'dart:convert';
import 'dart:io';

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

/// TLS 握手失败：证书过期、自签名、不受信任，或与主机名不匹配。
///
/// **不能**只看 `DioExceptionType.badCertificate`：实测（Android/iOS 共用的
/// `dart:io` + BoringSSL）证书过期时 dio 给的是 `DioExceptionType.unknown`
/// 包着 `HandshakeException`。所以统一按底层异常类型判断。
class KomgaTlsError extends KomgaError {
  const KomgaTlsError(super.message, {super.cause});
}

/// 这个端口只说 HTTPS：用户把 `https://` 写成了 `http://`。
///
/// 实测 openresty 反代对明文请求直接回 `400` + HTML
/// `The plain HTTP request was sent to HTTPS port`。这既不是"地址不对"也不是
/// "服务端拒绝参数"，需要单独成类，调用方才能自动换协议重试。
class KomgaHttpsRequiredError extends KomgaError {
  const KomgaHttpsRequiredError(super.message, {super.cause})
    : super(statusCode: 400);
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
  // 证书问题必须最先拦：dio 把它包成 `unknown`，再往下走会被当成
  // "网络不可达"，于是用户看到"检查网络"，而真正该做的是信任/续期证书。
  if (e.error is HandshakeException) {
    return KomgaTlsError('TLS 握手失败：服务器证书不受信任', cause: e);
  }
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
      final detail = _serverText(e.response?.data);
      final suffix = detail == null ? '' : '：$detail';
      if (status == 401 || status == 403) {
        return KomgaAuthError('认证失败（$status）', statusCode: status, cause: e);
      }
      if (status == 404) return KomgaNotFoundError('资源不存在（404）', cause: e);
      if (status == 400) {
        // 反代在"明文打到 HTTPS 端口"时回的就是 400，正文是 HTML。
        // 必须扫**原始 body**：Apache 的提示在正文里，<title> 只有 "Bad Request"。
        final raw = e.response?.data;
        final onlyHttps = raw is String && _plainHttpToHttpsPort.hasMatch(raw);
        if (onlyHttps) {
          return KomgaHttpsRequiredError(
            '这个端口只接受 HTTPS：${detail ?? '服务器要求 HTTPS'}',
            cause: e,
          );
        }
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

/// 反代对"明文请求打到 HTTPS 端口"的两种经典回法（nginx/openresty 与 Apache）。
final RegExp _plainHttpToHttpsPort = RegExp(
  r'(plain http request was sent to https port'
  r'|speaking plain http to an ssl-enabled server port)',
  caseSensitive: false,
);

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

/// 从响应体里抠出一句能给人看的话。
///
/// 形态比想象中杂，全都要容忍：
/// - Spring 错误体：`{"timestamp":…,"status":400,"message":"…"}`；
/// - 校验失败：`{"violations":[{"field":"…","message":"…"}]}`；
/// - 机器码：`{"message":"ERR_1034"}`——人类可读文案缺失，只能靠码判断；
/// - **空 body**（实测 `page=0` 的 400）；
/// - **反代的 HTML 错误页**（nginx/openresty）：不抠出来，用户就只看到 "400"。
String? _serverText(Object? data) {
  final map = _asJsonMap(data);
  if (map != null) {
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
  if (data is! String) return null;
  final raw = data.trim();
  if (raw.isEmpty) return null;
  final text = raw.contains('<') ? _htmlText(raw) : raw;
  if (text.isEmpty) return null;
  // 只取一句：错误提示位放不下整页。
  return text.length <= 200 ? text : '${text.substring(0, 197)}…';
}

/// 从 HTML 错误页里取标题（`<title>` 或 `<h1>`），取不到就把标签剥掉。
String _htmlText(String raw) {
  for (final pattern in <RegExp>[
    RegExp(r'<title>([\s\S]*?)</title>', caseSensitive: false),
    RegExp(r'<h1>([\s\S]*?)</h1>', caseSensitive: false),
    RegExp(r'<center>([\s\S]*?)</center>', caseSensitive: false),
  ]) {
    final text = pattern.firstMatch(raw)?.group(1);
    if (text == null) continue;
    final cleaned = _stripTags(text);
    if (cleaned.isNotEmpty) return cleaned;
  }
  return _stripTags(raw);
}

String _stripTags(String raw) => raw
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
