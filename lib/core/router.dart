import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/room/room_screen.dart';
import 'package:himi_syncwatch/screens/category/category_screen.dart';
import 'package:himi_syncwatch/screens/settings/settings_screen.dart';
import 'package:himi_syncwatch/screens/servers/server_manager_screen.dart';
import 'package:himi_syncwatch/screens/agora/agora_config_screen.dart';
import 'package:himi_syncwatch/screens/shell/main_shell.dart';

final routerKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: routerKey,
    initialLocation: '/',
    routes: [
      // 四标签壳：首页 / Emby服务器 / 声网配置 / 设置
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(shell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/servers',
              builder: (context, state) => const ServerManagerScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/agora',
              builder: (context, state) => const AgoraConfigScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: '/category/:id',
        builder: (context, state) => CategoryScreen(
          libraryId: state.pathParameters['id']!,
          libraryName: state.uri.queryParameters['name'],
          collectionType: state.uri.queryParameters['type'],
        ),
      ),
      GoRoute(
        path: '/detail/:id',
        builder: (context, state) => DetailScreen(
          itemId: state.pathParameters['id']!,
          roomMode: state.uri.queryParameters['roomMode'] == 'true',
          roomCode: state.uri.queryParameters['roomCode'],
          serverId: state.uri.queryParameters['server'],
        ),
      ),
      GoRoute(
        path: '/player/:id',
        builder: (context, state) {
          return PlayerScreen(
            itemId: state.pathParameters['id']!,
            roomCode: state.uri.queryParameters['roomCode'],
            mediaSourceId: state.uri.queryParameters['mediaSourceId'],
            isHost: state.uri.queryParameters['isHost'] == 'true',
            audienceName: state.uri.queryParameters['name'] ?? '',
            serverId: state.uri.queryParameters['server'],
          );
        },
      ),
      GoRoute(
        path: '/room',
        builder: (context, state) => RoomScreen(
          roomCode: state.uri.queryParameters['code'] ?? '',
          audienceName: state.uri.queryParameters['name'] ?? '',
        ),
      ),
    ],
  );
});
