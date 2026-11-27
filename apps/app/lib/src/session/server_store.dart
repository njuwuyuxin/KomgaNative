import 'dart:convert';

import 'package:flutter/foundation.dart' show FlutterError, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/data/secure_storage.dart';

/// 已保存的服务器会话。
///
/// 只保存 **API Key**，不保存密码：首次连接时用密码换一次 Key，之后密码即丢弃。
class StoredServer {
  const StoredServer({
    required this.address,
    required this.apiKey,
    required this.accountEmail,
    this.accountId = '',
    this.certificateFingerprint,
    this.kind = SourceKind.komga,
  });

  final ServerAddress address;
  final String apiKey;
  final String accountEmail;
  final String accountId;

  /// 服务器协议种类（默认为 [SourceKind.komga]，为 Kavita / OPDS 预留）。
  final SourceKind kind;

  /// 用户手动接受过的服务端证书指纹（SHA-256，小写无分隔符）。
  ///
  /// 非空表示"这台服务器的证书系统不认，但用户点了仍然连接"：
  /// 之后所有请求只放行这张证书，证书一换就必须重新询问。
  final String? certificateFingerprint;

  /// 服务器身份：同一台服务器换账号只保留最后一条（内容相同，没必要存两份）。
  String get id => address.baseUrl;

  /// 建会话时用的信任策略。
  TlsTrust get tls => certificateFingerprint == null
      ? TlsTrust.strict()
      : TlsTrust.pinned(certificateFingerprint!);

  /// 展示名：优先账号邮箱，没有就用地址。
  String get label => accountEmail.isEmpty ? address.baseUrl : accountEmail;

  StoredServer copyWith({String? certificateFingerprint, SourceKind? kind}) =>
      StoredServer(
        address: address,
        apiKey: apiKey,
        accountEmail: accountEmail,
        accountId: accountId,
        certificateFingerprint:
            certificateFingerprint ?? this.certificateFingerprint,
        kind: kind ?? this.kind,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'baseUrl': address.baseUrl,
    'apiKey': apiKey,
    'accountEmail': accountEmail,
    'accountId': accountId,
    if (kind != SourceKind.komga) 'kind': kind.name,
    if (certificateFingerprint != null)
      'certificateFingerprint': certificateFingerprint,
  };

  @override
  bool operator ==(Object other) =>
      other is StoredServer &&
      other.address == address &&
      other.apiKey == apiKey &&
      other.accountEmail == accountEmail &&
      other.accountId == accountId &&
      other.certificateFingerprint == certificateFingerprint &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(
    address,
    apiKey,
    accountEmail,
    accountId,
    certificateFingerprint,
    kind,
  );

  static StoredServer fromJson(Map<String, Object?> json) {
    // 存档可能被任何人写过（旧版本/手工改过），字段类型一律先判再取，
    // 不能因为一个脏字段就把整个会话读崩。
    final fingerprint = json['certificateFingerprint'];
    final rawKind = json['kind'];
    return StoredServer(
      address: ServerAddress.parse((json['baseUrl'] as String?) ?? ''),
      apiKey: (json['apiKey'] as String?) ?? '',
      accountEmail: (json['accountEmail'] as String?) ?? '',
      accountId: (json['accountId'] as String?) ?? '',
      certificateFingerprint: fingerprint is String
          ? _fingerprintOrNull(fingerprint)
          : null,
      kind: rawKind is String ? SourceKind.parse(rawKind) : SourceKind.komga,
    );
  }

  /// 存储里的指纹必须能通过校验，否则宁可当"没信任过"——
  /// 不能让一条脏数据把 TLS 校验降级。
  static String? _fingerprintOrNull(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return TlsTrust.normalizeFingerprint(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => 'StoredServer(${address.baseUrl}, $accountEmail)';
}

/// 会话持久化。抽象出来是为了让"连接流程"的测试不依赖钥匙串。
///
/// 多服务器语义：
/// - [load] 返回**当前活动**服务器；
/// - [save] 保存并设为活动（同一地址覆盖旧记录）；
/// - [all] 返回全部已保存服务器；
/// - [remove] 删掉某一台（若它是活动服务器，活动指针一并清空）；
/// - [clear] 只清"活动"标记，不删列表（"Disconnect" 不等于"忘掉所有服务器"）。
abstract interface class ServerStore {
  Future<StoredServer?> load();

  Future<List<StoredServer>> all();

  Future<void> save(StoredServer server);

  Future<void> remove(StoredServer server);

  Future<void> clear();
}

/// 真机实现：Keychain / Keystore。
///
/// 用一个 JSON blob 存全部服务器信息，避免多次跨平台调用，也避免把 API Key 拆成明文文件。
/// v2 格式：`{"active": {...}, "servers": [{...}, ...]}`；
/// 读到 v1（直接是一个 server 对象）时自动升级，不让老用户掉登录。
class SecureServerStore implements ServerStore {
  SecureServerStore({FlutterSecureStorage? storage})
    : _storage = storage ?? createAppSecureStorage();

  static const String _key = 'komganative.server.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredServer?> load() async {
    final state = await _read();
    return state.active;
  }

  @override
  Future<List<StoredServer>> all() async => (await _read()).servers;

  @override
  Future<void> save(StoredServer server) async {
    final state = await _read();
    final servers = <StoredServer>[
      for (final existing in state.servers)
        if (existing.id != server.id) existing,
      server,
    ];
    await _write(_ServerState(active: server, servers: servers));
  }

  @override
  Future<void> remove(StoredServer server) async {
    final state = await _read();
    final servers = state.servers
        .where((StoredServer s) => s.id != server.id)
        .toList(growable: false);
    final active = state.active?.id == server.id ? null : state.active;
    await _write(_ServerState(active: active, servers: servers));
  }

  @override
  Future<void> clear() async {
    final state = await _read();
    await _write(_ServerState(active: null, servers: state.servers));
  }

  Future<_ServerState> _read() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _key);
    } on FlutterError {
      // 无 Flutter 绑定的纯单元测试未覆写 ServerStore 时安全回退空列表。
      return const _ServerState();
    } on Exception {
      // Android 换机/密钥失效时自动清掉坏条目，避免后续重新登录也跟着报错。
      try {
        await _storage.delete(key: _key);
      } on Exception catch (error) {
        // 清理失败不阻断本次按空状态恢复。
        debugPrint('ServerStore: delete corrupted key failed: $error');
      }
      return const _ServerState();
    }
    if (raw == null || raw.isEmpty) return const _ServerState();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return const _ServerState();

      // v2
      final servers = decoded['servers'];
      if (servers is List<Object?>) {
        final list = servers
            .whereType<Map<Object?, Object?>>()
            .map(_toServer)
            .whereType<StoredServer>()
            .where((StoredServer s) => s.apiKey.isNotEmpty)
            .toList(growable: false);
        final activeRaw = decoded['active'];
        final active = activeRaw is Map<Object?, Object?>
            ? _toServer(activeRaw)
            : null;
        return _ServerState(
          active: (active != null && active.apiKey.isNotEmpty) ? active : null,
          servers: list,
        );
      }

      // v1：整个 blob 就是一个 server
      final legacy = _toServer(decoded);
      if (legacy == null || legacy.apiKey.isEmpty) return const _ServerState();
      return _ServerState(active: legacy, servers: <StoredServer>[legacy]);
    } on FormatException {
      return const _ServerState();
    }
  }

  Future<void> _write(_ServerState state) async {
    if (state.servers.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(
      key: _key,
      value: jsonEncode(<String, Object?>{
        'active': state.active?.toJson(),
        'servers': <Object?>[
          for (final server in state.servers) server.toJson(),
        ],
      }),
    );
  }

  static StoredServer? _toServer(Map<Object?, Object?> json) {
    try {
      return StoredServer.fromJson(Map<String, Object?>.from(json));
    } on FormatException {
      // 地址非法（手工改过/别的 App 的 key）就当这条不存在。
      return null;
    }
  }
}

class _ServerState {
  const _ServerState({this.active, this.servers = const <StoredServer>[]});

  final StoredServer? active;
  final List<StoredServer> servers;
}

/// 测试/预览用。
class InMemoryServerStore implements ServerStore {
  InMemoryServerStore([StoredServer? server])
    : _active = server,
      _servers = server == null ? <StoredServer>[] : <StoredServer>[server];

  /// 直接给多台（设置页/切换测试用）。
  InMemoryServerStore.withAll(
    List<StoredServer> servers, {
    StoredServer? active,
  }) : _active = active,
       _servers = List<StoredServer>.of(servers);

  StoredServer? _active;
  List<StoredServer> _servers;

  @override
  Future<StoredServer?> load() async => _active;

  @override
  Future<List<StoredServer>> all() async => List<StoredServer>.of(_servers);

  @override
  Future<void> save(StoredServer server) async {
    _servers = <StoredServer>[
      for (final existing in _servers)
        if (existing.id != server.id) existing,
      server,
    ];
    _active = server;
  }

  @override
  Future<void> remove(StoredServer server) async {
    _servers = _servers
        .where((StoredServer s) => s.id != server.id)
        .toList(growable: false);
    if (_active?.id == server.id) _active = null;
  }

  @override
  Future<void> clear() async => _active = null;
}
