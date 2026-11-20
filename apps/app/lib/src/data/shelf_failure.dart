import 'package:komga_api/komga_api.dart';

/// 书架层对 UI 暴露的失败类型。
///
/// 为什么不让 UI 直接用 `KomgaError`：`screens/**` 禁止 import `komga_api`
/// （分层规则），而且 UI 需要的是"能不能重试 / 要不要重新登录"这种语义，
/// 不是 HTTP 细节。由数据层在这里一次性翻译。
///
/// 文案暂用英文，与其余 UI 一致；i18n 切片会连同 ARB 与中文字体一起处理。
/// 失败的种类（I18N-01）：UI 按它查本地化文案，不再显示数据层写死的英文。
///
/// `unexpected` 是兜底：未知类型也必须有一句人话，不能把裸异常扔给用户。
enum ShelfFailureKind {
  auth,
  network,
  server,
  protocol,
  certificate,
  unexpected,
}

sealed class ShelfFailure implements Exception {
  const ShelfFailure(this.message, {this.hint});

  /// 本地化用的种类标签。
  ShelfFailureKind get kind;

  /// 一句话说明，直接进 `StatusView.title`。
  final String message;

  /// 可操作建议，进 `StatusView.message`。
  final String? hint;

  @override
  String toString() => '$runtimeType: $message';
}

/// 凭据失效：重试没用，必须重新连接。
class AuthFailure extends ShelfFailure {
  @override
  ShelfFailureKind get kind => ShelfFailureKind.auth;

  const AuthFailure()
    : super(
        'Session expired',
        hint: 'This API key may have been revoked. Sign out and connect again.',
      );
}

/// 网络不可达：可以重试，通常是地址/网络问题。
class NetworkFailure extends ShelfFailure {
  @override
  ShelfFailureKind get kind => ShelfFailureKind.network;

  const NetworkFailure()
    : super(
        'Cannot reach the server',
        hint: 'Check that this device and the server are on the same network.',
      );
}

/// 服务端 5xx：可退避重试。
class ServerFailure extends ShelfFailure {
  @override
  ShelfFailureKind get kind => ShelfFailureKind.server;

  const ServerFailure()
    : super(
        'Server error',
        hint: 'Try again later; check the Komga server logs if it persists.',
      );
}

/// 请求被拒/响应不可解析：多半是版本或反向代理问题。
class ProtocolFailure extends ShelfFailure {
  @override
  ShelfFailureKind get kind => ShelfFailureKind.protocol;

  const ProtocolFailure()
    : super(
        'Unexpected server response',
        hint: 'Make sure this address is Komga and the proxy is not rewriting it.',
      );
}

/// 证书不再受信任：用户接受过的那张证书变了（续期/被替换）。
///
/// 必须重新走一次连接流程让用户确认——静默接受新证书等于把 TOFU 作废。
class CertificateFailure extends ShelfFailure {
  @override
  ShelfFailureKind get kind => ShelfFailureKind.certificate;

  const CertificateFailure()
    : super(
        'Server certificate changed',
        hint: 'Reconnect and review the certificate before trusting it again.',
      );
}

/// 404：资源（书/系列/收藏集）在服务端已被删除，原样重试不会恢复。
class NotFoundFailure extends ShelfFailure {
  @override
  ShelfFailureKind get kind => ShelfFailureKind.protocol;

  const NotFoundFailure()
    : super(
        'Resource not found',
        hint: 'This item may have been removed from the server.',
      );
}

/// 400：请求参数被服务端拒绝（如页码越界），原样重放只会永久失败。
class BadRequestFailure extends ShelfFailure {
  @override
  ShelfFailureKind get kind => ShelfFailureKind.protocol;

  const BadRequestFailure()
    : super(
        'Request rejected by server',
        hint: 'Refresh from the server and try again.',
      );
}

/// 兜底：不该发生，但绝不让 UI 看到裸异常。
class UnexpectedFailure extends ShelfFailure {
  @override
  ShelfFailureKind get kind => ShelfFailureKind.unexpected;

  const UnexpectedFailure(this.detail)
    : super('Failed to load', hint: 'Pull to refresh to try again.');

  final String detail;
}

/// 把 `KomgaError`（sealed）翻译成 UI 语义。
ShelfFailure shelfFailureOf(KomgaError error) => switch (error) {
  KomgaAuthError() => const AuthFailure(),
  KomgaNetworkError() => const NetworkFailure(),
  KomgaServerError() => const ServerFailure(),
  KomgaCancelledError() => const NetworkFailure(),
  KomgaTlsError() => const CertificateFailure(),
  KomgaNotFoundError() => const NotFoundFailure(),
  KomgaBadRequestError() => const BadRequestFailure(),
  KomgaProtocolError() || KomgaHttpsRequiredError() => const ProtocolFailure(),
};
