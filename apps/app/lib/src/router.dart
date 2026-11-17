import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:komga_native/src/screens/library_screen.dart';
import 'package:komga_native/src/screens/reader_screen.dart';
import 'package:komga_native/src/screens/settings_screen.dart';
import 'package:komga_native/src/widgets/adaptive_shell.dart';

/// 路由表。
///
/// 约定：
/// - 主界面用 `StatefulShellRoute.indexedStack`，切 tab 时保留各自滚动位置；
/// - 阅读器是**根导航**上的全屏路由（不显示导航栏），返回即退出阅读。
GoRouter createRouter({String initialLocation = '/library'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
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
