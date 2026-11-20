import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/session/certificate_prompt.dart';
import 'package:komga_native/src/session/connection_service.dart';
import 'package:komga_native/src/session/server_store.dart';

/// 会话状态。UI 只 switch 它，不自己维护"是否登录"的布尔。
sealed class SessionState {
  const SessionState();
}

/// 启动中：正在从钥匙串读取上次的会话。
class SessionLoading extends SessionState {
  const SessionLoading();
}

/// 未连接。携带本次连接尝试的失败信息（没有就是首次进入）。
class SessionDisconnected extends SessionState {
  const SessionDisconnected({
    this.error,
    this.hint,
    this.submitting = false,
    this.certificate,
  });

  final String? error;

  /// 给用户的可操作建议，与 [error] 分开是为了 UI 层级清晰。
  final String? hint;

  final bool submitting;

  /// 非空表示"系统不认这张证书"，等用户决定是否信任。
  ///
  /// 界面据此展示指纹/颁发者/有效期，并提供"仍然连接"；点了之后
  /// [SessionController.trustCertificate] 用固定指纹重试。
  final CertificatePrompt? certificate;
}

class SessionConnected extends SessionState {
  const SessionConnected(this.server);

  final StoredServer server;
}

/// 一次连接尝试：给定地址与 TLS 信任策略，返回结果。
///
/// 抽成闭包是因为"密码模式"和"API Key 模式"只差凭据，而重试逻辑
/// （换协议、信任证书后重试）两者完全一样。
typedef _ConnectAction = Future<ConnectionOutcome> Function(
  ServerAddress address,
  TlsTrust trust,
);

/// 会话控制器：负责"从钥匙串恢复 / 连接 / 退出"。
///
/// 网络与存储都从 provider 取，测试里 override 即可脱离真机与网络。
class SessionController extends Notifier<SessionState> {
  /// 上一个失败的尝试，用于"信任证书后重试"——不重新收集用户输入。
  _ConnectAction? _pendingAction;

  /// 上一次实际尝试的地址。可能是自动从 http 升级出来的 https。
  ServerAddress? _pendingAddress;

  /// 上一次抓到的证书原文（信任重试要用它的完整指纹）。
  ServerCertificate? _pendingCertificate;

  @override
  SessionState build() {
    // 启动即恢复，但不阻塞首帧（UI 先渲染 splash）。
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
    } on Object catch (e) {
      if (!ref.mounted || state is! SessionLoading) return;
      state = SessionDisconnected(error: '无法读取已保存的会话', hint: '$e');
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
            // 从 Komga 后台复制 Key 时常带首尾空白/换行，统一裁掉。
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
    } on FormatException catch (e) {
      state = SessionDisconnected(
        error: e.message,
        hint: '示例：https://komga.example.com 或 http://192.168.1.10:25600',
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

  /// 用户看过证书详情后点"仍然连接"。
  ///
  /// 用**这张证书的指纹**重试，成功则把指纹一起持久化：以后只放行同一张证书，
  /// 换了证书（续期、中间人）会再次询问，不会静默放行。
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
      // 信任是有代价的：只有把指纹一起存下来，之后每次请求才只放行这张证书。
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
        // 用户把 https 端口写成了 http：反代对明文请求直接回 400。
        // 自动换协议重试一次；成功后保存的就是 https 地址，用户不必自己改。
        if (!allowHttpsUpgrade || effective.isHttps) rethrow;
        effective = effective.withScheme('https');
        _pendingAddress = effective;
        outcome = await action(effective, trust);
      }
      final saved = trustFingerprint == null
          ? outcome.server
          : outcome.server.copyWith(certificateFingerprint: trustFingerprint);
      await _store.save(saved);
      _pendingAction = null;
      _pendingCertificate = null;
      state = SessionConnected(saved);
    } on KomgaAuthError {
      state = const SessionDisconnected(
        error: '账号或密码不正确',
        hint: '如果服务端开了双步验证，请改用 API Key 方式连接',
      );
    } on KomgaTlsError {
      // 证书细节要摊开给用户看：只报"证书错误"没法让人做决定。
      _pendingAddress = effective;
      final certificate = await _service.probeCertificate(effective);
      _pendingCertificate = certificate;
      state = SessionDisconnected(
        error: 'The server’s certificate is not trusted',
        hint: certificate == null
            ? 'The connection failed before the certificate could be read.'
            : null,
        certificate: certificate == null
            ? null
            : CertificatePrompt.from(certificate),
      );
    } on KomgaHttpsRequiredError {
      state = SessionDisconnected(
        error: 'This port speaks HTTPS only',
        hint: effective.isHttps
            ? 'The server on ${effective.baseUrl} refused the connection.'
            : 'Try ${effective.withScheme('https').baseUrl} instead.',
      );
    } on KomgaNetworkError {
      state = SessionDisconnected(
        error: '无法连接到 ${effective.host}',
        hint: '检查地址/端口，以及手机是否和服务端在同一网络',
      );
    } on KomgaBadRequestError catch (e) {
      // 走到这里说明地址/端口能通，但服务端或反代拒绝了请求。
      state = SessionDisconnected(
        error: 'The server refused the request',
        hint: e.message,
      );
    } on KomgaServerError catch (e) {
      state = SessionDisconnected(
        error: '服务器出错了（${e.statusCode ?? '5xx'}）',
        hint: '稍后重试；若持续失败，检查 Komga 服务端日志',
      );
    } on KomgaProtocolError catch (e) {
      state = SessionDisconnected(
        error: e.message,
        hint: '这个地址可能不是 Komga，或被反向代理改写成了网页',
      );
    } on Object catch (e) {
      state = SessionDisconnected(error: '连接失败', hint: '$e');
    }
  }

  /// 用户放弃信任（关掉证书面板）。
  void cancelCertificatePrompt() {
    _pendingCertificate = null;
    state = const SessionDisconnected();
  }

  /// 切换到一个已保存的服务器（不重新验证 Key；失效时用请求的 401 兜底）。
  ///
  /// 先把活动服务器写回存储，再切状态：这样"切换后杀掉进程"也能恢复到新的那台。
  Future<void> switchTo(StoredServer server) async {
    await _store.save(server);
    state = SessionConnected(server);
  }

  Future<void> signOut() async {
    _pendingAction = null;
    _pendingAddress = null;
    _pendingCertificate = null;
    // 只清"活动"标记：多服务器列表里别的服务器不该被一次 Disconnect 忘掉。
    await _store.clear();
    state = const SessionDisconnected();
  }

  /// 删除一台已保存的服务器；若它正是当前活动服务器则一并登出（ARC-05）。
  Future<void> removeServer(StoredServer server) async {
    final current = state;
    await _store.remove(server);
    ref.invalidate(serverListProvider);
    if (current is SessionConnected && current.server.id == server.id) {
      await signOut();
    }
  }
}

final Provider<ServerStore> serverStoreProvider = Provider<ServerStore>(
  (Ref ref) => SecureServerStore(),
);

final Provider<ConnectionService> connectionServiceProvider =
    Provider<ConnectionService>((Ref ref) => LiveConnectionService());

/// 已保存的服务器列表（设置页展示/切换）。
final serverListProvider = FutureProvider<List<StoredServer>>((Ref ref) {
  return ref.watch(serverStoreProvider).all();
});

final NotifierProvider<SessionController, SessionState> sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
