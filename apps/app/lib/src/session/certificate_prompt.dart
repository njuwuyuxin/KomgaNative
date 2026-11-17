import 'package:komga_api/komga_api.dart';

/// 给用户看的证书信息（纯值对象，不含任何网络能力）。
///
/// 界面层不允许 import `komga_api`（分层规则），所以由会话层把
/// [ServerCertificate] 折成这个只需要文案的小对象。
class CertificatePrompt {
  const CertificatePrompt({
    required this.commonName,
    required this.issuerName,
    required this.fingerprint,
    required this.selfSigned,
    this.expiresAt,
  });

  factory CertificatePrompt.from(ServerCertificate certificate) {
    return CertificatePrompt(
      commonName: certificate.commonName,
      issuerName: certificate.issuerName,
      fingerprint: certificate.displayFingerprint,
      selfSigned: certificate.isSelfSigned,
      expiresAt: certificate.notAfter,
    );
  }

  /// 证书上的 CN（`*.yasai.site`）。
  final String commonName;

  /// 颁发者 CN（`E7`、`R3`…）。
  final String issuerName;

  /// 前 8 字节的可读指纹，界面用来做"眼见为实"的核对。
  final String fingerprint;

  final bool selfSigned;
  final DateTime? expiresAt;

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// `2026-07-19`（证书有效期是 UTC，展示也只说日期，避免时区误解）。
  ///
  /// 没有到期时间时返回空串：文案由界面层用本地化的"未知"补上。
  String get expiresText {
    final date = expiresAt;
    if (date == null) return '';
    final utc = date.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day';
  }
}
