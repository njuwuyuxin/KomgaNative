import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/session/server_store.dart';

class ConnectionOutcome {
  const ConnectionOutcome({required this.server, required this.libraries});

  final StoredServer server;
  final List<Library> libraries;
}

/// 连接 Komga 的两条路径。
///
/// - 密码模式：校验凭据 → **自动创建 API Key** → 只保存 Key（用户下次不用再输密码）；
/// - API Key 模式：给已经在 Web 后台建好 Key 的用户（或不想让客户端碰密码的用户）。
///
/// [trust] 是 TLS 信任策略：默认严格校验；用户接受过某张证书后传
/// `TlsTrust.pinned(指纹)`，只放行那张。
abstract interface class ConnectionService {
  Future<ConnectionOutcome> connectWithPassword({
    required ServerAddress address,
    required String username,
    required String password,
    TlsTrust? trust,
  });

  Future<ConnectionOutcome> connectWithApiKey({
    required ServerAddress address,
    required String apiKey,
    TlsTrust? trust,
  });

  /// 抓取该地址实际出示的证书（不校验、不带凭据），用于"证书不受信任"面板。
  Future<ServerCertificate?> probeCertificate(ServerAddress address);
}

class LiveConnectionService implements ConnectionService {
  LiveConnectionService({this.deviceLabel = 'Yomu'});

  /// 写进 API Key 的 comment，方便用户在 Komga 后台识别并随时吊销。
  final String deviceLabel;

  @override
  Future<ConnectionOutcome> connectWithPassword({
    required ServerAddress address,
    required String username,
    required String password,
    TlsTrust? trust,
  }) async {
    final basic = KomgaSession.withBasic(
      address: address,
      username: username,
      password: password,
      trust: trust,
    );
    try {
      // 先用一次真实请求验凭据（同时拿到库列表，省一次往返）。
      final libraries = await basic.fetchLibraries();
      final key = await basic.createApiKey(comment: deviceLabel);
      final apiKeySession = KomgaSession.withApiKey(
        address: address,
        apiKey: key,
        trust: trust,
      );
      final Account account;
      try {
        account = await apiKeySession.fetchAccount();
      } finally {
        apiKeySession.close();
      }
      return ConnectionOutcome(
        server: StoredServer(
          address: address,
          apiKey: key,
          accountEmail: account.email,
          accountId: account.id,
        ),
        libraries: libraries,
      );
    } finally {
      basic.close();
    }
  }

  @override
  Future<ConnectionOutcome> connectWithApiKey({
    required ServerAddress address,
    required String apiKey,
    TlsTrust? trust,
  }) async {
    final session = KomgaSession.withApiKey(
      address: address,
      apiKey: apiKey,
      trust: trust,
    );
    try {
      final account = await session.fetchAccount();
      final libraries = await session.fetchLibraries();
      return ConnectionOutcome(
        server: StoredServer(
          address: address,
          apiKey: apiKey,
          accountEmail: account.email,
          accountId: account.id,
        ),
        libraries: libraries,
      );
    } finally {
      session.close();
    }
  }

  @override
  Future<ServerCertificate?> probeCertificate(ServerAddress address) =>
      KomgaSession.probeCertificate(address: address);
}
