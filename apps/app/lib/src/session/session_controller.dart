import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_domain/komga_domain.dart';
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
  const SessionDisconnected({this.error, this.hint, this.submitting = false});

  final String? error;

  /// 给用户的可操作建议，与 [error] 分开是为了 UI 层级清晰。
  final String? hint;

  final bool submitting;
}

class SessionConnected extends SessionState {
  const SessionConnected(this.server);

  final StoredServer server;
}

/// 会话控制器：负责"从钥匙串恢复 / 连接 / 退出"。
///
/// 网络与存储都从 provider 取，测试里 override 即可脱离真机与网络。
class SessionController extends Notifier<SessionState> {
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
      // 读钥匙串期间用户可能已经点过 Connect：不能被"旧状态"覆盖回去。
      if (state is! SessionLoading) return;
      state = saved == null
          ? const SessionDisconnected()
          : SessionConnected(saved);
    } on Object catch (e) {
      if (state is! SessionLoading) return;
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
      action: (ServerAddress address) => _service.connectWithPassword(
        address: address,
        username: username,
        password: password,
      ),
    );
  }

  Future<void> connectWithApiKey({
    required String rawUrl,
    required String apiKey,
  }) {
    return _connect(
      rawUrl: rawUrl,
      action: (ServerAddress address) => _service.connectWithApiKey(
        address: address,
        // 从 Komga 后台复制 Key 时常带首尾空白/换行，统一裁掉。
        apiKey: apiKey.trim(),
      ),
    );
  }

  Future<void> _connect({
    required String rawUrl,
    required Future<ConnectionOutcome> Function(ServerAddress address) action,
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

    try {
      final outcome = await action(address);
      await _store.save(outcome.server);
      state = SessionConnected(outcome.server);
    } on KomgaAuthError {
      state = const SessionDisconnected(
        error: '账号或密码不正确',
        hint: '如果服务端开了双步验证，请改用 API Key 方式连接',
      );
    } on KomgaNetworkError {
      state = SessionDisconnected(
        error: '无法连接到 ${address.host}',
        hint: '检查地址/端口，以及手机是否和服务端在同一网络',
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

  Future<void> signOut() async {
    await _store.clear();
    state = const SessionDisconnected();
  }
}

final Provider<ServerStore> serverStoreProvider = Provider<ServerStore>(
  (Ref ref) => SecureServerStore(),
);

final Provider<ConnectionService> connectionServiceProvider =
    Provider<ConnectionService>((Ref ref) => LiveConnectionService());

final NotifierProvider<SessionController, SessionState> sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
