import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komga_domain/komga_domain.dart';

/// 已保存的服务器会话。
///
/// 只保存 **API Key**，不保存密码：首次连接时用密码换一次 Key，之后密码即丢弃。
class StoredServer {
  const StoredServer({
    required this.address,
    required this.apiKey,
    required this.accountEmail,
    this.accountId = '',
  });

  final ServerAddress address;
  final String apiKey;
  final String accountEmail;
  final String accountId;

  Map<String, Object?> toJson() => <String, Object?>{
    'baseUrl': address.baseUrl,
    'apiKey': apiKey,
    'accountEmail': accountEmail,
    'accountId': accountId,
  };

  static StoredServer fromJson(Map<String, Object?> json) => StoredServer(
    address: ServerAddress.parse((json['baseUrl'] as String?) ?? ''),
    apiKey: (json['apiKey'] as String?) ?? '',
    accountEmail: (json['accountEmail'] as String?) ?? '',
    accountId: (json['accountId'] as String?) ?? '',
  );

  @override
  String toString() => 'StoredServer(${address.baseUrl}, $accountEmail)';
}

/// 会话持久化。抽象出来是为了让"连接流程"的测试不依赖钥匙串。
abstract interface class ServerStore {
  Future<StoredServer?> load();

  Future<void> save(StoredServer server);

  Future<void> clear();
}

/// 真机实现：Keychain / Keystore。
///
/// 用一个 JSON blob 存全部会话信息，避免多次跨平台调用，也避免把 API Key 拆成明文文件。
class SecureServerStore implements ServerStore {
  SecureServerStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'komganative.server.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredServer?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final server = StoredServer.fromJson(decoded);
      // 损坏/空 Key 视为未登录，避免带着空 Key 去打服务器。
      if (server.apiKey.isEmpty) return null;
      return server;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(StoredServer server) =>
      _storage.write(key: _key, value: jsonEncode(server.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// 测试/预览用。
class InMemoryServerStore implements ServerStore {
  InMemoryServerStore([this._server]);

  StoredServer? _server;

  @override
  Future<StoredServer?> load() async => _server;

  @override
  Future<void> save(StoredServer server) async => _server = server;

  @override
  Future<void> clear() async => _server = null;
}
