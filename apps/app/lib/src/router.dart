import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:yomu_domain/yomu_domain.dart';
import 'package:yomu/src/screens/collection_detail_screen.dart';
import 'package:yomu/src/screens/collections_screen.dart';
import 'package:yomu/src/screens/connection_screen.dart';
import 'package:yomu/src/screens/downloads_screen.dart';
import 'package:yomu/src/screens/local_library_center_screen.dart';
import 'package:yomu/src/screens/readlist_detail_screen.dart';
import 'package:yomu/src/screens/search_screen.dart';
import 'package:yomu/src/screens/history_screen.dart';
import 'package:yomu/src/screens/insights_screen.dart';
import 'package:yomu/src/screens/library_screen.dart';
import 'package:yomu/src/screens/reader_screen.dart';
import 'package:yomu/src/screens/reading_now_screen.dart';
import 'package:yomu/src/screens/series_detail_args.dart';
import 'package:yomu/src/screens/series_detail_screen.dart';
import 'package:yomu/src/screens/settings_screen.dart';
import 'package:yomu/src/screens/splash_screen.dart';
import 'package:yomu/src/session/session_controller.dart';
import 'package:yomu/src/widgets/adaptive_shell.dart';
import 'package:yomu/src/widgets/scoped_source_scope.dart';
import 'package:yomu/src/widgets/sliding_branch_container.dart';
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
      // 恢复完成后：无论是否连接远程服务器，均免登录直达主壳首页（ADR 0008）；
      // 仅当用户在 /connect 完成登录成为 SessionConnected 时自动返回首页。
      if (location == '/splash') return '/reading';
      if (current is SessionConnected && location == '/connect') {
        return '/reading';
      }
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
      StatefulShellRoute(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell shell,
        ) => AdaptiveShell(shell: shell),
        // 主页面切换用水平滑动（旧页滑出 / 新页滑入），而不是默认的
        // IndexedStack 瞬切；分支持久化与返回栈仍由 go_router 负责。
        navigatorContainerBuilder:
            (
              BuildContext context,
              StatefulNavigationShell shell,
              List<Widget> children,
            ) => SlidingBranchContainer(
              currentIndex: shell.currentIndex,
              children: children,
            ),
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
          // 收藏集也是底部 dock 的一个 tab（与书架并列，见 AdaptiveShell）；
          // 详情页仍是顶层 push，返回时回到这支分支。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/collections',
                builder: (BuildContext context, GoRouterState state) =>
                    const CollectionsScreen(),
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
          // 搜索分支放在最后（与手机端右下角搜索球位置一致），确保从正在读 / 书架 /
          // 收藏 / 设置任意页面进入搜索都从右侧滑入、返回时向右滑出。
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/search',
                builder: (BuildContext context, GoRouterState state) =>
                    const SearchScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/insights',
        builder: (BuildContext context, GoRouterState state) =>
            const InsightsScreen(),
      ),
      // 历史页是**顶层路由**，不能塞进某个 shell branch：
      // 一个 branch 只能有一个根路由，放进去会让设置标签跳到历史页（踩过）。
      GoRoute(
        path: '/history',
        builder: (BuildContext context, GoRouterState state) =>
            const HistoryScreen(),
      ),
      GoRoute(
        path: '/downloads',
        builder: (BuildContext context, GoRouterState state) =>
            const DownloadsScreen(),
      ),
      GoRoute(
        path: '/local-library',
        builder: (BuildContext context, GoRouterState state) =>
            const LocalLibraryCenterScreen(),
      ),
      GoRoute(
        path: '/collections/:collectionId',
        builder: (BuildContext context, GoRouterState state) =>
            CollectionDetailScreen(
              collectionId: state.pathParameters['collectionId'] ?? '',
              title: state.extra is String ? state.extra! as String : null,
            ),
      ),
      GoRoute(
        path: '/readlists/:readListId',
        builder: (BuildContext context, GoRouterState state) =>
            ReadListDetailScreen(
              readListId: state.pathParameters['readListId'] ?? '',
              title: state.extra is String ? state.extra! as String : null,
            ),
      ),
      GoRoute(
        path: '/series/:seriesId',
        builder: (BuildContext context, GoRouterState state) {
          final extra = state.extra;
          final args = extra is SeriesDetailArgs ? extra : null;
          final resolvedSource =
              state.uri.queryParameters['source'] ?? args?.sourceKey;
          return ScopedSourceScope(
            sourceKey: resolvedSource,
            child: SeriesDetailScreen(
              seriesId: state.pathParameters['seriesId'] ?? '',
              heroTag: args?.heroTag,
            ),
          );
        },
      ),
      GoRoute(
        path: '/reader/:bookId',
        builder: (BuildContext context, GoRouterState state) {
          final extra = state.extra;
          final args = extra is ReaderArgs ? extra : null;
          final resolvedSource =
              state.uri.queryParameters['source'] ??
              args?.sourceKey ??
              args?.book.sourceKey;
          return ScopedSourceScope(
            sourceKey: resolvedSource,
            child: ReaderScreen(
              bookId: state.pathParameters['bookId'] ?? '',
              book: args?.book,
              direction: args?.direction ?? ReadingDirection.unknown,
              heroTag: args?.heroTag,
            ),
          );
        },
      ),
    ],
  );
}
