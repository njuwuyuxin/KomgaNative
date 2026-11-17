import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 服务端证书里我们真正需要的那几个字段。
///
/// 自己建模而不是到处传 `X509Certificate`：`X509Certificate` 无法在测试里构造，
/// 而这里要断言"过期了没有 / 是不是自签名 / 指纹怎么显示"。
class ServerCertificate {
  const ServerCertificate({
    required this.derSha256,
    required this.subject,
    required this.issuer,
    this.notBefore,
    this.notAfter,
  });

  /// 从原始 DER 构造。指纹一律算出来，不接受外部传入——
  /// 指纹是"我信任的到底是哪张证书"的唯一依据，不能靠调用方给。
  factory ServerCertificate.fromDer(
    List<int> der, {
    String subject = '',
    String issuer = '',
    DateTime? notBefore,
    DateTime? notAfter,
  }) {
    return ServerCertificate(
      derSha256: sha256.convert(der).toString(),
      subject: subject,
      issuer: issuer,
      notBefore: notBefore,
      notAfter: notAfter,
    );
  }

  factory ServerCertificate.from(X509Certificate certificate) {
    return ServerCertificate.fromDer(
      certificate.der,
      subject: certificate.subject,
      issuer: certificate.issuer,
      notBefore: certificate.startValidity,
      notAfter: certificate.endValidity,
    );
  }

  /// 叶证书 DER 的 SHA-256，**小写、无分隔符**。比较与持久化都用这个形态；
  /// 界面展示用 [displayFingerprint]。
  final String derSha256;

  final String subject;
  final String issuer;
  final DateTime? notBefore;
  final DateTime? notAfter;

  /// `/CN=*.yasai.site` → `*.yasai.site`。取不到 CN 就退回整个 DN。
  String get commonName => _fieldOf(subject, 'CN') ?? subject;

  String get issuerName => _fieldOf(issuer, 'CN') ?? issuer;

  /// 自签名证书的判据是"颁发者 == 主体"，这也是客户端要额外信任它的原因。
  bool get isSelfSigned => issuer.isNotEmpty && issuer == subject;

  bool isExpiredAt(DateTime now) => notAfter != null && notAfter!.isBefore(now);

  bool get isExpired => isExpiredAt(DateTime.now());

  /// 可读指纹：`CB:BD:C4:31:A9:FD:55:EB:…`，前 8 字节足够人眼核对。
  String get displayFingerprint {
    final bytes = <String>[];
    for (var i = 0; i + 1 < derSha256.length && bytes.length < 8; i += 2) {
      bytes.add(derSha256.substring(i, i + 2).toUpperCase());
    }
    return bytes.join(':');
  }

  @override
  String toString() => 'ServerCertificate($commonName, $derSha256)';
}

/// 证书信任策略。
///
/// 三种用法：
/// - [TlsTrust.strict]：系统默认校验，不碰任何证书错误（默认值）；
/// - [TlsTrust.pinned]：用户已明确接受过这张证书，只放行**指纹完全一致**的那张；
/// - [TlsTrust.probe]：只把证书抓下来给用户看，一律拒绝，不发送任何凭据。
///
/// 固定指纹（而不是"接受所有证书"）是关键：自建服务器的证书过期/自签名很常见，
/// 但一旦用户接受了某张证书，之后换了一张（中间人、DNS 劫持）就必须重新询问。
class TlsTrust {
  TlsTrust.strict() : _pinnedSha256 = null, _isProbe = false;

  TlsTrust.pinned(String fingerprint)
    : _pinnedSha256 = normalizeFingerprint(fingerprint),
      _isProbe = false;

  TlsTrust.probe() : _pinnedSha256 = null, _isProbe = true;

  final String? _pinnedSha256;
  final bool _isProbe;

  ServerCertificate? _presented;

  /// [TlsTrust.probe] 抓到的证书；握手没走到这一步时为 null。
  ServerCertificate? get presented => _presented;

  bool get isProbe => _isProbe;

  /// 固定住的指纹；strict 与 probe 都是 null。
  String? get pinnedSha256 => _pinnedSha256;

  /// 默认的系统校验（不额外信任任何证书）。
  bool get isStrict => _pinnedSha256 == null && !_isProbe;

  /// 是否允许这张证书通过。抽成独立方法是为了能在测试里直接喂
  /// [ServerCertificate]，不必真起一个 TLS 服务器。
  bool allows(ServerCertificate certificate) {
    _presented = certificate;
    if (_isProbe) return false;
    final pinned = _pinnedSha256;
    return pinned != null && pinned == certificate.derSha256;
  }

  /// `badCertificateCallback` 的适配层。
  bool _onBadCertificate(X509Certificate certificate, String host, int port) {
    return allows(ServerCertificate.from(certificate));
  }

  /// 给 `Dio.httpClientAdapter` 用的适配器。
  ///
  /// 注意：dio 5.11 的 `validateCertificate` 只声明、没有真正接到 `HttpClient` 上，
  /// 所以必须走 `createHttpClient` + `badCertificateCallback`。
  HttpClientAdapter adapter() {
    return IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient()..idleTimeout = const Duration(seconds: 3);
        client.badCertificateCallback = _onBadCertificate;
        return client;
      },
    );
  }

  /// 指纹输入容错：去分隔符、忽略大小写（用户可能从浏览器/openssl 里抄）。
  static String normalizeFingerprint(String raw) {
    final compact = raw.replaceAll(RegExp('[^0-9a-fA-F]'), '').toLowerCase();
    if (compact.length != 64) {
      throw FormatException(
        'Certificate fingerprint must be 64 hex characters, got ${compact.length}',
      );
    }
    return compact;
  }
}

/// 从 DN 里取某个字段：`/C=US/O=Let's Encrypt/CN=E7` → `E7`。
///
/// dart:io 给的是 `/` 分隔的 OpenSSL 风格；也兼容 `CN=…, O=…` 的逗号风格。
String? _fieldOf(String dn, String key) {
  final pattern = RegExp('(?:^|[/,])\\s*$key=([^/,]+)');
  final match = pattern.firstMatch(dn);
  return match?.group(1)?.trim();
}
