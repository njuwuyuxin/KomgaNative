import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_native/src/router.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:material_ui/material_ui.dart';

/// 把 Riverpod 的会话状态桥接成 go_router 能监听的对象。
///
/// 这是唯一一处"把 provider 变化翻译成路由刷新"的地方，页面里不再有登录判断。
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final ValueNotifier<SessionState> session = ValueNotifier<SessionState>(
    ref.read(sessionProvider),
  );
  ref.listen<SessionState>(sessionProvider, (
    SessionState? previous,
    SessionState next,
  ) {
    session.value = next;
  });
  ref.onDispose(session.dispose);
  return createRouter(session: session);
});
