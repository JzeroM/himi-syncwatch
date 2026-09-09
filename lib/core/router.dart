import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himi_syncwatch/screens/home/home_screen.dart';
import 'package:himi_syncwatch/screens/detail/detail_screen.dart';
import 'package:himi_syncwatch/screens/player/player_screen.dart';
import 'package:himi_syncwatch/screens/room/room_screen.dart';
import 'package:himi_syncwatch/screens/category/category_screen.dart';

final routerKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: routerKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
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
        ),
      ),
      GoRoute(
        path: '/player/:id',
        builder: (context, state) {
          List<Map<String, dynamic>>? episodes;
          final episodesJson = state.uri.queryParameters['episodes'];
          if (episodesJson != null && episodesJson.isNotEmpty) {
            try {
              final decoded = jsonDecode(Uri.decodeComponent(episodesJson));
              if (decoded is List) {
                episodes = decoded.cast<Map<String, dynamic>>();
              }
            } catch (_) {}
          }
          Map<String, dynamic>? movie;
          final movieJson = state.uri.queryParameters['movie'];
          if (movieJson != null && movieJson.isNotEmpty) {
            try {
              final decoded = jsonDecode(Uri.decodeComponent(movieJson));
              if (decoded is Map) {
                movie = decoded.cast<String, dynamic>();
              }
            } catch (_) {}
          }
          return PlayerScreen(
            itemId: state.pathParameters['id']!,
            roomCode: state.uri.queryParameters['roomCode'],
            mediaSourceId: state.uri.queryParameters['mediaSourceId'],
            isHost: state.uri.queryParameters['isHost'] == 'true',
            audienceName: state.uri.queryParameters['name'] ?? '',
            episodes: episodes,
            movie: movie,
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
