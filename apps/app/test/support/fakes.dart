import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/session/connection_service.dart';
import 'package:komga_native/src/session/server_store.dart';

/// 可控的假连接服务：按需成功/抛出指定错误。
class FakeConnectionService implements ConnectionService {
  FakeConnectionService({this.onConnect, this.onProbe});

  /// 返回 null 表示成功（用默认结果），抛异常表示失败。
  /// 参数里带上了信任策略，测试可以断言"重试时用的是固定指纹"。
  final Future<ConnectionOutcome> Function(
    ServerAddress address,
    TlsTrust trust,
  )?
  onConnect;

  final Future<ServerCertificate?> Function(ServerAddress address)? onProbe;

  int passwordCalls = 0;
  int apiKeyCalls = 0;
  int probeCalls = 0;
  ServerAddress? lastAddress;
  String? lastApiKey;

  /// 每次尝试用的信任策略，按调用顺序记录。
  final List<TlsTrust> trusts = <TlsTrust>[];

  @override
  Future<ConnectionOutcome> connectWithPassword({
    required ServerAddress address,
    required String username,
    required String password,
    TlsTrust? trust,
  }) {
    passwordCalls++;
    lastAddress = address;
    return _run(address, trust);
  }

  @override
  Future<ConnectionOutcome> connectWithApiKey({
    required ServerAddress address,
    required String apiKey,
    TlsTrust? trust,
  }) {
    apiKeyCalls++;
    lastAddress = address;
    lastApiKey = apiKey;
    return _run(address, trust);
  }

  Future<ConnectionOutcome> _run(ServerAddress address, TlsTrust? trust) {
    final effective = trust ?? TlsTrust.strict();
    trusts.add(effective);
    final handler = onConnect;
    if (handler == null) {
      return Future<ConnectionOutcome>.value(connectedOutcome(address));
    }
    return handler(address, effective);
  }

  @override
  Future<ServerCertificate?> probeCertificate(ServerAddress address) {
    probeCalls++;
    final handler = onProbe;
    if (handler != null) return handler(address);
    return Future<ServerCertificate?>.value(expiredCertificate());
  }
}

ConnectionOutcome connectedOutcome(ServerAddress address) => ConnectionOutcome(
  server: StoredServer(
    address: address,
    apiKey: 'KEY-1',
    accountEmail: 'me@example.com',
    accountId: 'u1',
  ),
  libraries: const <Library>[Library(id: 'lib1', name: 'Comics')],
);

StoredServer storedServer() => StoredServer(
  address: ServerAddress.parse('https://komga.example.com'),
  apiKey: 'KEY-1',
  accountEmail: 'me@example.com',
  accountId: 'u1',
);

/// 与实测一致的一组证书字段：CN、Let's Encrypt 颁发者、2026-07-19 到期。
ServerCertificate expiredCertificate() => ServerCertificate.fromDer(
  const <int>[1, 2, 3, 4, 5],
  subject: '/CN=*.yasai.site',
  issuer: "/C=US/O=Let's Encrypt/CN=E7",
  notBefore: DateTime.utc(2026, 4, 19),
  notAfter: DateTime.utc(2026, 7, 19, 11, 26, 15),
);

/// 常用错误构造，避免测试里重复写 dio 细节。
KomgaAuthError authError() => const KomgaAuthError('401');
KomgaNetworkError networkError() => const KomgaNetworkError('refused');
KomgaServerError serverError() =>
    const KomgaServerError('503', statusCode: 503);
KomgaTlsError tlsError() => const KomgaTlsError('TLS 握手失败');
KomgaHttpsRequiredError httpsRequiredError() =>
    const KomgaHttpsRequiredError('这个端口只接受 HTTPS');
