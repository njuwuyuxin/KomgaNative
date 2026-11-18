import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_domain/komga_domain.dart';
import 'package:komga_native/src/screens/connection_screen.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/reading_now_screen.dart';
import 'package:komga_native/src/screens/series_detail_screen.dart';
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
      // 已连接：不要再停留在启动/连接页；首页是"正在读"（UI-P2-6）。
      if (location == '/splash' || location == '/connect') return '/reading';
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
          // "正在读"是首页（UI-P2-6）：打开 App 先看到"上次看到哪"。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/reading',
                builder: (BuildContext context, GoRouterState state) =>
                    const ReadingNowScreen(),
              ),
            ],
          ),
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
        path: '/series/:seriesId',
        builder: (BuildContext context, GoRouterState state) =>
            SeriesDetailScreen(
              seriesId: state.pathParameters['seriesId'] ?? '',
            ),
      ),
      GoRoute(
        path: '/reader/:bookId',
        builder: (BuildContext context, GoRouterState state) {
          // 从系列详情点进来时会带上 Book 与阅读方向，省一次请求；
          // 冷启动/深链没有 extra 时由阅读器自己取书。
          final extra = state.extra;
          final args = extra is ReaderArgs ? extra : null;
          return ReaderScreen(
            bookId: state.pathParameters['bookId'] ?? '',
            book: args?.book,
            direction: args?.direction ?? ReadingDirection.unknown,
          );
        },
      ),
    ],
  );
}
