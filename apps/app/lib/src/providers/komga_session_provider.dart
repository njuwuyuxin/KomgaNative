import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:yomu/src/providers/cache_providers.dart';
import 'package:yomu/src/session/server_store.dart';
import 'package:yomu/src/session/session_controller.dart';

StoredServer? _findServer(List<StoredServer> servers, String serverId) {
  for (final server in servers) {
    if (server.id == serverId) return server;
  }
  return null;
}

/// 按服务器 ID（规范化 `baseUrl`）精准订阅单台服务器配置。
///
/// 利用 [StoredServer] 值相等性隔离其余服务器的增删与切换，
/// 避免切换或修改 B 服务器时误触发 A 服务器的会话与缓存重建（P1-3）。
final storedServerByIdProvider = Provider.family<StoredServer?, String>((
  Ref ref,
  String serverId,
) {
  if (serverId.isEmpty) return null;
  final connected = ref.watch(
    sessionProvider.select((SessionState state) {
      if (state is SessionConnected && state.server.id == serverId) {
        return state.server;
      }
      return null;
    }),
  );
  if (connected != null) return connected;
  return ref.watch(
    serverListProvider.select(
      (AsyncValue<List<StoredServer>> list) =>
          _findServer(list.value ?? const <StoredServer>[], serverId),
    ),
  );
});

/// 按服务器标识（规范化 `baseUrl`）懒创建并缓存 [KomgaSession]。
///
/// - 仅在被实际访问时才实例化对应服务器的连接池，并随该服务器生命周期自动关闭；
/// - 其余服务器变更或切换浏览源时不会销毁重建本服务器的连接池（P1-3）；
/// - 未找到对应服务器时返回 `null`。
final komgaSessionForServerProvider = Provider.family<KomgaSession?, String>((
  Ref ref,
  String serverId,
) {
  if (serverId.isEmpty) return ref.watch(komgaSessionProvider);
  final matched = ref.watch(storedServerByIdProvider(serverId));
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

/// 当前已连接会话共享的 [KomgaSession]（复用 [komgaSessionForServerProvider] 避免重复建池）。
final Provider<KomgaSession?> komgaSessionProvider = Provider<KomgaSession?>((
  Ref ref,
) {
  final activeId = ref.watch(
    sessionProvider.select(
      (SessionState state) => state is SessionConnected ? state.server.id : '',
    ),
  );
  if (activeId.isEmpty) return null;
  return ref.watch(komgaSessionForServerProvider(activeId));
});

/// 获取当前必选的共享 [KomgaSession]；未连接时抛 [StateError] 暴露错误接线。
KomgaSession requireKomgaSession(Ref ref, {String reason = '未连接服务器'}) {
  final komga = ref.watch(komgaSessionProvider);
  if (komga == null) throw StateError(reason);
  return komga;
}
