import 'package:komga_api/komga_api.dart';
import 'package:test/test.dart';

void main() {
  group('ServerCertificate', () {
    // 已知答案测试：DER 固定为 [1,2,3,4,5]，SHA-256 由外部工具算出。
    // 指纹是"信任哪张证书"的唯一凭据，算错等于把安全判断建在流沙上。
    const der = <int>[1, 2, 3, 4, 5];
    const derSha256 =
        '74f81fe167d99b4cb41d6d0ccda82278caee9f3e2f25d5e5a3936ff3dcec60d0';

    ServerCertificate sample() => ServerCertificate.fromDer(
      der,
      subject: '/CN=*.yasai.site',
      issuer: "/C=US/O=Let's Encrypt/CN=E7",
      notBefore: DateTime.utc(2026, 4, 19),
      notAfter: DateTime.utc(2026, 7, 19, 11, 26, 15),
    );

    test('指纹是 DER 的 SHA-256，小写无分隔符', () {
      expect(sample().derSha256, derSha256);
    });

    test('展示指纹取前 8 字节、大写、冒号分隔', () {
      expect(sample().displayFingerprint, '74:F8:1F:E1:67:D9:9B:4C');
    });

    test('CN 从 DN 里抠出来，兼容 / 与 , 两种写法', () {
      expect(sample().commonName, '*.yasai.site');
      expect(sample().issuerName, 'E7');
      // 逗号风格（部分平台/工具的输出）
      final comma = ServerCertificate.fromDer(
        der,
        subject: 'CN=nas.local, O=Home',
        issuer: 'CN=nas.local, O=Home',
      );
      expect(comma.commonName, 'nas.local');
      expect(comma.issuerName, 'nas.local');
    });

    test('取不到 CN 时退回整个 DN，而不是空串', () {
      final cert = ServerCertificate.fromDer(der, subject: '/O=Home');
      expect(cert.commonName, '/O=Home');
    });

    test('过期判断基于给定时刻（不在测试里读系统时钟）', () {
      final cert = sample();
      expect(cert.isExpiredAt(DateTime.utc(2026, 7, 18)), isFalse);
      expect(cert.isExpiredAt(DateTime.utc(2026, 7, 20)), isTrue);
      // 到期当天、时间点之后也算过期
      expect(cert.isExpiredAt(DateTime.utc(2026, 7, 19, 12)), isTrue);
    });

    test('自签名 = 颁发者与主体相同', () {
      expect(sample().isSelfSigned, isFalse);
      expect(
        ServerCertificate.fromDer(
          der,
          subject: '/CN=nas',
          issuer: '/CN=nas',
        ).isSelfSigned,
        isTrue,
      );
    });
  });

  group('TlsTrust', () {
    ServerCertificate cert(String seed) =>
        ServerCertificate.fromDer(<int>[seed.codeUnitAt(0)]);
    final issued = cert('a');
    final other = cert('b');

    test('strict 不放行任何异常证书（默认策略）', () {
      final trust = TlsTrust.strict();
      expect(trust.allows(issued), isFalse);
      expect(trust.presented, same(issued));
    });

    test('pinned 只放行指纹一致的那一张', () {
      final trust = TlsTrust.pinned(issued.derSha256);
      expect(trust.allows(issued), isTrue);
      expect(trust.allows(other), isFalse, reason: '换证书必须重新询问');
    });

    test('probe 抓下证书但一律拒绝（不带凭据的探测）', () {
      final trust = TlsTrust.probe();
      expect(trust.allows(issued), isFalse);
      expect(trust.presented, same(issued));
      expect(trust.isProbe, isTrue);
    });

    test('指纹输入容错：大小写、冒号、空格都能用', () {
      final upper = issued.derSha256.toUpperCase();
      expect(TlsTrust.normalizeFingerprint(upper), issued.derSha256);
      final coloned = issued.derSha256.replaceAllMapped(
        RegExp('..'),
        (m) => '${m[0]}:',
      );
      expect(TlsTrust.normalizeFingerprint(coloned), issued.derSha256);
      expect(
        TlsTrust.normalizeFingerprint('  ${issued.derSha256}  '),
        issued.derSha256,
      );
    });

    test('指纹长度不对就报错，不静默接受', () {
      expect(
        () => TlsTrust.normalizeFingerprint('abc'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => TlsTrust.normalizeFingerprint('zz' * 32),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
