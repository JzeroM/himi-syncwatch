import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/favorites_provider.dart';

import '../helpers/test_fakes.dart';

void main() {
  group('FavoriteGroups.fromItems', () {
    test('按 Type 分为 电影/电视剧/集，忽略其它类型', () {
      final groups = FavoriteGroups.fromItems([
        MediaItem(id: 'm1', name: '电影', type: 'Movie'),
        MediaItem(id: 's1', name: '剧集', type: 'Series'),
        MediaItem(id: 'e1', name: '第1集', type: 'Episode'),
        MediaItem(id: 'e2', name: '第2集', type: 'Episode'),
        MediaItem(id: 'x1', name: '季', type: 'Season'),
      ]);

      expect(groups.movies.map((e) => e.id), ['m1']);
      expect(groups.series.map((e) => e.id), ['s1']);
      expect(groups.episodes.map((e) => e.id), ['e1', 'e2']);
      expect(groups.isEmpty, isFalse);
    });

    test('空列表 → isEmpty', () {
      expect(FavoriteGroups.fromItems(const []).isEmpty, isTrue);
    });
  });

  group('aggregateFavoriteItemsProvider', () {
    EmbyServerConfig server(String id) => EmbyServerConfig(
          id: id,
          serverUrl: 'http://$id',
          serverName: id,
          serverId: '$id-sid',
          username: 'u',
          accessToken: 't',
          userId: 'uid',
        );

    test('跨服务器按 TMDB id 去重，代表项优先当前服务器', () async {
      final s1 = server('s1');
      final s2 = server('s2');
      final services = {
        's1': FakeEmbyService(favoriteItems: [
          MediaItem(
            id: 's1-m1',
            name: '电影一',
            type: 'Movie',
            providerIds: const {'Tmdb': '1'},
          ),
          MediaItem(
            id: 's1-m2',
            name: '电影二',
            type: 'Movie',
            providerIds: const {'Tmdb': '2'},
          ),
        ]),
        's2': FakeEmbyService(favoriteItems: [
          MediaItem(
            id: 's2-m1',
            name: '电影一',
            type: 'Movie',
            providerIds: const {'Tmdb': '1'},
          ),
        ]),
      };
      final container = ProviderContainer(overrides: [
        embyServiceFactoryProvider.overrideWithValue((s) => services[s.id]!),
      ]);
      addTearDown(container.dispose);
      container.read(embyServerListProvider.notifier).setList([s1, s2]);
      container.read(embyConfigProvider.notifier).setConfig(s2);

      final groups =
          await container.read(aggregateFavoriteItemsProvider.future);

      expect(groups.movies.map((e) => e.item.id), ['s2-m1', 's1-m2']);
      expect(groups.movies.first.server?.id, 's2');
      expect(groups.failedServerCount, 0);
    });

    test('单台服务器失败不阻塞其它服务器', () async {
      final s1 = server('s1');
      final s2 = server('s2');
      final container = ProviderContainer(overrides: [
        embyServiceFactoryProvider.overrideWithValue((s) {
          if (s.id == 's1') throw StateError('down');
          return FakeEmbyService(favoriteItems: [
            MediaItem(
              id: 's2-m1',
              name: '电影',
              type: 'Movie',
              providerIds: const {'Tmdb': '1'},
            ),
          ]);
        }),
      ]);
      addTearDown(container.dispose);
      container.read(embyServerListProvider.notifier).setList([s1, s2]);

      final groups =
          await container.read(aggregateFavoriteItemsProvider.future);

      expect(groups.movies.single.item.id, 's2-m1');
      expect(groups.failedServerCount, 1);
    });
  });
}
