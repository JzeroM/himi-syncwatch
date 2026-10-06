import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/app_settings.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/favorites_provider.dart';
import 'package:himi_syncwatch/providers/settings_provider.dart';
import 'package:himi_syncwatch/screens/favorites/favorites_screen.dart';
import 'package:himi_syncwatch/widgets/favorite_episode_card.dart';
import 'package:himi_syncwatch/widgets/poster_card.dart';

import '../helpers/test_fakes.dart';

Future<void> _pump(WidgetTester tester, FavoriteGroups groups,
    {AppSettings settings = const AppSettings()}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => FakeSettingsNotifier(settings)),
        favoriteItemsProvider.overrideWith((ref) async => groups),
      ],
      child: const MaterialApp(home: FavoritesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('三分区：电影 / 电视剧 / 集，各自「查看所有」入口', (tester) async {
    await _pump(
      tester,
      FavoriteGroups.fromItems([
        MediaItem(id: 'm1', name: '电影A', type: 'Movie', posterUrl: null),
        MediaItem(id: 's1', name: '剧集A', type: 'Series', posterUrl: null),
        MediaItem(
            id: 'e1',
            name: '热狗',
            type: 'Episode',
            seriesName: '某剧',
            indexNumber: 1),
      ]),
    );

    expect(find.text('电影'), findsOneWidget);
    expect(find.text('电视剧'), findsOneWidget);
    expect(find.text('集'), findsOneWidget);

    expect(find.byKey(const Key('favoritesViewAll_movie')), findsOneWidget);
    expect(find.byKey(const Key('favoritesViewAll_series')), findsOneWidget);
    expect(find.byKey(const Key('favoritesViewAll_episode')), findsOneWidget);

    // 电影/电视剧用海报卡，集用横版卡
    expect(find.byType(PosterCard), findsNWidgets(2));
    expect(find.byType(FavoriteEpisodeCard), findsOneWidget);
    expect(find.text('热狗'), findsOneWidget);
  });

  testWidgets('空收藏 → 空态，无分区', (tester) async {
    await _pump(tester, const FavoriteGroups());

    expect(find.textContaining('还没有收藏'), findsOneWidget);
    expect(find.text('电影'), findsNothing);
    expect(find.byKey(const Key('favoritesViewAll_movie')), findsNothing);
  });

  testWidgets('只有电影时仅渲染电影分区', (tester) async {
    await _pump(
      tester,
      FavoriteGroups.fromItems([
        MediaItem(id: 'm1', name: '电影A', type: 'Movie'),
      ]),
    );

    expect(find.text('电影'), findsOneWidget);
    expect(find.text('电视剧'), findsNothing);
    expect(find.text('集'), findsNothing);
  });
}
