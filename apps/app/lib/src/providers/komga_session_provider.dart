import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';

/// 当前已连接会话共享的唯一 [KomgaSession]（含统一 `Dio` 连接池、`TlsTrust` 与 `HttpCache`）。
///
/// 未连接时返回 `null`；切换服务器或退出登录时由 Riverpod 在此处唯一执行 `close()`（ARC-09）。
final Provider<KomgaSession?> komgaSessionProvider = Provider<KomgaSession?>((
  Ref ref,
) {
  final session = ref.watch(sessionProvider);
  if (session is! SessionConnected) return null;
  final komga = KomgaSession.withApiKey(
    address: session.server.address,
    apiKey: session.server.apiKey,
    trust: session.server.tls,
    cache: ref.watch(httpCacheProvider),
  );
  ref.onDispose(komga.close);
  return komga;
});

/// 按服务器标识（规范化 `baseUrl`）懒创建并缓存 [KomgaSession]。
///
/// - 目标为当前活动服务器时直接复用 [komgaSessionProvider]；
/// - 否则按已保存服务器凭证创建独立会话并随 provider 生命周期自动关闭；
/// - 未找到对应服务器时返回 `null`。
final komgaSessionForServerProvider = Provider.family<KomgaSession?, String>((
  Ref ref,
  String serverId,
) {
  if (serverId.isEmpty) return ref.watch(komgaSessionProvider);
  final active = ref.watch(komgaSessionProvider);
  if (active != null && active.address.baseUrl == serverId) return active;

  final servers = ref.watch(serverListProvider).value ?? const <StoredServer>[];
  StoredServer? matched;
  for (final server in servers) {
    if (server.id == serverId) {
      matched = server;
      break;
    }
  }
  if (matched == null) return null;

  final komga = KomgaSession.withApiKey(
    address: matched.address,
    apiKey: matched.apiKey,
    trust: matched.tls,
    cache: ref.watch(httpCacheProvider),
  );
  ref.onDispose(komga.close);
  return komga;
});

/// 获取当前必选的共享 [KomgaSession]；未连接时抛 [StateError] 暴露错误接线。
KomgaSession requireKomgaSession(Ref ref, {String reason = '未连接服务器'}) {
  final komga = ref.watch(komgaSessionProvider);
  if (komga == null) throw StateError(reason);
  return komga;
}
