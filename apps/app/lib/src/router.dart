import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_native/src/screens/connection_screen.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/screens/splash_screen.dart';
import 'package:komga_native/src/session/session_controller.dart';
import 'package:komga_native/src/widgets/adaptive_shell.dart';
import 'package:material_ui/material_ui.dart';

/// 路由表 + 登录态守卫。
///
/// 守卫放在路由层（而不是每个页面里 `if (!loggedIn)`），保证：
/// 深链、返回栈、冷启动三条路径行为一致。
GoRouter createRouter({
  required ValueListenable<SessionState> session,
  String initialLocation = '/splash',
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: session,
    redirect: (BuildContext context, GoRouterState state) {
      final current = session.value;
      final location = state.matchedLocation;

      if (current is SessionLoading) {
        return location == '/splash' ? null : '/splash';
      }
      if (current is SessionDisconnected) {
        return location == '/connect' ? null : '/connect';
      }
      // 已连接：不要再停留在启动/连接页。
      if (location == '/splash' || location == '/connect') return '/library';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/splash',
        builder: (BuildContext context, GoRouterState state) =>
            const SplashScreen(),
      ),
      GoRoute(
        path: '/connect',
        builder: (BuildContext context, GoRouterState state) =>
            const ConnectionScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) => AdaptiveShell(shell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/library',
                builder: (BuildContext context, GoRouterState state) =>
                    const LibraryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (BuildContext context, GoRouterState state) =>
                    const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/reader/:bookId',
        builder: (BuildContext context, GoRouterState state) =>
            ReaderScreen(bookId: state.pathParameters['bookId'] ?? ''),
      ),
    ],
  );
}
