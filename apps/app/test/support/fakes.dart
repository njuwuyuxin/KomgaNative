import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/session/connection_service.dart';
import 'package:komga_native/src/session/server_store.dart';

/// 可控的假连接服务：按需成功/抛出指定错误。
class FakeConnectionService implements ConnectionService {
  FakeConnectionService({this.onConnect});

  /// 返回 null 表示成功（用默认结果），抛异常表示失败。
  final Future<ConnectionOutcome> Function(ServerAddress address)? onConnect;

  int passwordCalls = 0;
  int apiKeyCalls = 0;
  ServerAddress? lastAddress;
  String? lastApiKey;

  @override
  Future<ConnectionOutcome> connectWithPassword({
    required ServerAddress address,
    required String username,
    required String password,
  }) {
    passwordCalls++;
    lastAddress = address;
    final handler = onConnect;
    if (handler == null)
      return Future<ConnectionOutcome>.value(connectedOutcome(address));
    return handler(address);
  }

  @override
  Future<ConnectionOutcome> connectWithApiKey({
    required ServerAddress address,
    required String apiKey,
  }) {
    apiKeyCalls++;
    lastAddress = address;
    lastApiKey = apiKey;
    final handler = onConnect;
    if (handler == null)
      return Future<ConnectionOutcome>.value(connectedOutcome(address));
    return handler(address);
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

/// 常用错误构造，避免测试里重复写 dio 细节。
KomgaAuthError authError() => const KomgaAuthError('401');
KomgaNetworkError networkError() => const KomgaNetworkError('refused');
KomgaServerError serverError() =>
    const KomgaServerError('503', statusCode: 503);
