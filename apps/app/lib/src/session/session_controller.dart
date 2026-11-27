import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/providers/progress_providers.dart';
import 'package:yomu/src/session/certificate_prompt.dart';
import 'package:yomu/src/session/connection_service.dart';
import 'package:yomu/src/session/server_store.dart';

/// 连接失败的结构化种类（ARC-11：UI 按当前 Locale 渲染，消除中英硬编码混排）。
enum ConnectionFailureKind {
  restoreFailed,
  invalidAddress,
  auth,
  untrustedCertificate,
  httpsRequired,
  httpsRefused,
  network,
  badRequest,
  server,
  protocol,
  unexpected,
}

/// 结构化连接失败详情（不携带固定语种文案）。
class ConnectionFailure {
  const ConnectionFailure(
    this.kind, {
    this.host,
    this.url,
    this.statusCode,
    this.certificateUnreadable = false,
  });

  final ConnectionFailureKind kind;
  final String? host;
  final String? url;
  final int? statusCode;
  final bool certificateUnreadable;
}

/// 会话状态。UI 只 switch 它，不自己维护"是否登录"的布尔。
sealed class SessionState {
  const SessionState();
}

/// 启动中：正在从钥匙串读取上次的会话。
class SessionLoading extends SessionState {
  const SessionLoading();
}

/// 未连接。携带本次连接尝试的结构化失败信息（没有就是首次进入）。
class SessionDisconnected extends SessionState {
  const SessionDisconnected({
    this.failure,
    this.submitting = false,
    this.certificate,
  });

  final ConnectionFailure? failure;
  final bool submitting;

  /// 非空表示"系统不认这张证书"，等用户决定是否信任。
  final CertificatePrompt? certificate;
}

class SessionConnected extends SessionState {
  const SessionConnected(this.server);

  final StoredServer server;
}

typedef _ConnectAction = Future<ConnectionOutcome> Function(
  ServerAddress address,
  TlsTrust trust,
);

/// 会话控制器：负责"从钥匙串恢复 / 连接 / 退出"。
class SessionController extends Notifier<SessionState> {
  _ConnectAction? _pendingAction;
  ServerAddress? _pendingAddress;
  ServerCertificate? _pendingCertificate;

  @override
  SessionState build() {
    unawaited(_restore());
    return const SessionLoading();
  }

  ServerStore get _store => ref.read(serverStoreProvider);
  ConnectionService get _service => ref.read(connectionServiceProvider);

  Future<void> _restore() async {
    try {
      final saved = await _store.load();
      if (!ref.mounted || state is! SessionLoading) return;
      state = saved == null
          ? const SessionDisconnected()
          : SessionConnected(saved);
    } on Exception {
      if (!ref.mounted || state is! SessionLoading) return;
      state = const SessionDisconnected(
        failure: ConnectionFailure(ConnectionFailureKind.restoreFailed),
      );
    }
  }

  Future<void> connectWithPassword({
    required String rawUrl,
    required String username,
    required String password,
  }) {
    return _connect(
      rawUrl: rawUrl,
      action: (ServerAddress address, TlsTrust trust) =>
          _service.connectWithPassword(
            address: address,
            username: username,
            password: password,
            trust: trust,
          ),
    );
  }

  Future<void> connectWithApiKey({
    required String rawUrl,
    required String apiKey,
  }) {
    return _connect(
      rawUrl: rawUrl,
      action: (ServerAddress address, TlsTrust trust) =>
          _service.connectWithApiKey(
            address: address,
            apiKey: apiKey.trim(),
            trust: trust,
          ),
    );
  }

  Future<void> _connect({
    required String rawUrl,
    required _ConnectAction action,
  }) async {
    state = const SessionDisconnected(submitting: true);

    final ServerAddress address;
    try {
      address = ServerAddress.parse(rawUrl);
    } on FormatException {
      state = const SessionDisconnected(
        failure: ConnectionFailure(ConnectionFailureKind.invalidAddress),
      );
      return;
    }

    _pendingAction = action;
    _pendingAddress = address;
    _pendingCertificate = null;
    await _establish(
      action: action,
      address: address,
      trust: TlsTrust.strict(),
      allowHttpsUpgrade: true,
    );
  }

  Future<void> trustCertificate() async {
    final certificate = _pendingCertificate;
    final action = _pendingAction;
    final address = _pendingAddress;
    if (certificate == null || action == null || address == null) return;

    state = const SessionDisconnected(submitting: true);
    await _establish(
      action: action,
      address: address,
      trust: TlsTrust.pinned(certificate.derSha256),
      allowHttpsUpgrade: false,
      trustFingerprint: certificate.derSha256,
    );
  }

  Future<void> _establish({
    required _ConnectAction action,
    required ServerAddress address,
    required TlsTrust trust,
    required bool allowHttpsUpgrade,
    String? trustFingerprint,
  }) async {
    var effective = address;
    try {
      ConnectionOutcome outcome;
      try {
        outcome = await action(effective, trust);
      } on KomgaHttpsRequiredError {
        if (!allowHttpsUpgrade || effective.isHttps) rethrow;
        effective = effective.withScheme('https');
        _pendingAddress = effective;
        outcome = await action(effective, trust);
      }
      final saved = trustFingerprint == null
          ? outcome.server
          : outcome.server.copyWith(certificateFingerprint: trustFingerprint);
      await _store.save(saved);
      ref.invalidate(serverListProvider);
      _pendingAction = null;
      _pendingCertificate = null;
      state = SessionConnected(saved);
    } on KomgaAuthError {
      state = const SessionDisconnected(
        failure: ConnectionFailure(ConnectionFailureKind.auth),
      );
    } on KomgaTlsError {
      _pendingAddress = effective;
      final certificate = await _service.probeCertificate(effective);
      _pendingCertificate = certificate;
      state = SessionDisconnected(
        failure: ConnectionFailure(
          ConnectionFailureKind.untrustedCertificate,
          certificateUnreadable: certificate == null,
        ),
        certificate: certificate == null
            ? null
            : CertificatePrompt.from(certificate),
      );
    } on KomgaHttpsRequiredError {
      state = SessionDisconnected(
        failure: effective.isHttps
            ? ConnectionFailure(
                ConnectionFailureKind.httpsRefused,
                url: effective.baseUrl,
              )
            : ConnectionFailure(
                ConnectionFailureKind.httpsRequired,
                url: effective.withScheme('https').baseUrl,
              ),
      );
    } on KomgaNetworkError {
      state = SessionDisconnected(
        failure: ConnectionFailure(
          ConnectionFailureKind.network,
          host: effective.host,
        ),
      );
    } on KomgaBadRequestError {
      state = const SessionDisconnected(
        failure: ConnectionFailure(ConnectionFailureKind.badRequest),
      );
    } on KomgaServerError catch (e) {
      state = SessionDisconnected(
        failure: ConnectionFailure(
          ConnectionFailureKind.server,
          statusCode: e.statusCode,
        ),
      );
    } on KomgaProtocolError {
      state = const SessionDisconnected(
        failure: ConnectionFailure(ConnectionFailureKind.protocol),
      );
    } on Exception {
      state = const SessionDisconnected(
        failure: ConnectionFailure(ConnectionFailureKind.unexpected),
      );
    }
  }

  void cancelCertificatePrompt() {
    _pendingCertificate = null;
    state = const SessionDisconnected();
  }

  Future<void> switchTo(StoredServer server) async {
    await _store.save(server);
    state = SessionConnected(server);
  }

  Future<void> signOut() async {
    _pendingAction = null;
    _pendingAddress = null;
    _pendingCertificate = null;
    await _store.clear();
    state = const SessionDisconnected();
  }

  Future<void> removeServer(StoredServer server) async {
    final current = state;
    await _store.remove(server);
    ref.invalidate(serverListProvider);
    if (current is SessionConnected && current.server.id == server.id) {
      await signOut();
    }
    // 清理被删除服务器的进度、outbox 记录以及同步服务内存状态（P3）。
    // 持久层走 progressStoreProvider，内存态通过单向 scopeRemovedListenersProvider 广播，避免循环依赖。
    try {
      await ref.read(progressStoreProvider).clearScope(server.id);
    } on Exception catch (error) {
      debugPrint('SessionController: clearScope(${server.id}) failed: $error');
    }
    for (final listener in List<void Function(String)>.of(
      ref.read(scopeRemovedListenersProvider),
    )) {
      listener(server.id);
    }
  }
}

final Provider<ServerStore> serverStoreProvider = Provider<ServerStore>(
  (Ref ref) => SecureServerStore(),
);

final Provider<ConnectionService> connectionServiceProvider =
    Provider<ConnectionService>((Ref ref) => LiveConnectionService());

final serverListProvider = FutureProvider<List<StoredServer>>((Ref ref) {
  return ref.watch(serverStoreProvider).all();
});

final NotifierProvider<SessionController, SessionState> sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
