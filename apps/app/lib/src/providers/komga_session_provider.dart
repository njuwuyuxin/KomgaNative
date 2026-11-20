import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:komga_api/komga_api.dart';
import 'package:komga_native/src/providers/cache_providers.dart';
import 'package:komga_native/src/session/session_controller.dart';

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

/// 获取当前必选的共享 [KomgaSession]；未连接时抛 [StateError] 暴露错误接线。
KomgaSession requireKomgaSession(Ref ref, {String reason = '未连接服务器'}) {
  final komga = ref.watch(komgaSessionProvider);
  if (komga == null) throw StateError(reason);
  return komga;
}
