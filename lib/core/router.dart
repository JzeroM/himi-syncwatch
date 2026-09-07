import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/room/room_screen.dart';
import 'package:himi_syncwatch/screens/login/login_screen.dart';

final routerKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final config = ref.watch(embyConfigProvider);

  return GoRouter(
    navigatorKey: routerKey,
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = config != null && config.isAuthenticated;
      final isOnLogin = state.matchedLocation == '/login';

      if (isLoggedIn && isOnLogin) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/detail/:id',
        builder: (context, state) => DetailScreen(
          itemId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/player/:id',
        builder: (context, state) => PlayerScreen(
          itemId: state.pathParameters['id']!,
          roomId: state.uri.queryParameters['roomId'],
        ),
      ),
      GoRoute(
        path: '/room/:roomId',
        builder: (context, state) => RoomScreen(
          roomId: state.pathParameters['roomId']!,
        ),
      ),
    ],
  );
});
