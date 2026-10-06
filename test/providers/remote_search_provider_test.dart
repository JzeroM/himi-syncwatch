import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/providers/emby_provider.dart';
import 'package:himi_syncwatch/providers/remote_search_provider.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _server(String id, String name) => EmbyServerConfig(
      id: id,
      serverUrl: 'https://$id.example.com',
      serverName: name,
      serverId: 'srv-$id',
      username: 'user',
      accessToken: 'tok-$id',
      userId: 'uid',
    );

MediaItem _item(String id, String name, {String? posterUrl}) =>
    MediaItem(id: id, name: name, type: 'Movie', posterUrl: posterUrl);

ProviderContainer _container({List<EmbyServerConfig> servers = const []}) {
  final container = ProviderContainer(
    overrides: [
      remoteSearchBasePortProvider.overrideWithValue(0),
      if (servers.isNotEmpty)
        embyServerListProvider.overrideWith(
          (ref) => EmbyServerListNotifier()..setList(servers),
        ),
      globalSearchProvider.overrideWithValue(
        GlobalSearchService(
          serviceFactory: (cfg) => FakeEmbyService(
            searchResults: [
              _item(
                '${cfg.id}-1',
                '${cfg.serverName}的影片',
                posterUrl: 'https://${cfg.id}.example.com/p.jpg',
              ),
            ],
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  Future<ProviderContainer> start() async {
    final container = _container(servers: [_server('a', '服务器甲')]);
    final notifier = container.read(remoteSearchProvider.notifier);
    await notifier.start();
    return container;
  }

  test('start 后 running 且 url 带 token，stop 后状态复位', () async {
    final container = _container();
    final notifier = container.read(remoteSearchProvider.notifier);

    expect(container.read(remoteSearchProvider).running, isFalse);

    await notifier.start();
    final state = container.read(remoteSearchProvider);
    expect(state.running, isTrue);
    expect(state.url, startsWith('http://'));
    expect(state.url, contains('t='));
    expect(state.error, isNull);

    await notifier.stop();
    expect(container.read(remoteSearchProvider).running, isFalse);
    expect(container.read(remoteSearchProvider).url, isNull);
  });

  test('posterWithToken：海报地址追加 api_key（手机 img 直取）', () {
    expect(
      posterWithToken('https://a/p.jpg', 'tok'),
      'https://a/p.jpg?api_key=tok',
    );
    expect(
      posterWithToken('https://a/p.jpg?tag=x', 'tok'),
      'https://a/p.jpg?tag=x&api_key=tok',
    );
    expect(posterWithToken(null, 'tok'), isNull);
    expect(posterWithToken('', 'tok'), isNull);
    expect(posterWithToken('https://a/p.jpg', null), 'https://a/p.jpg');
    expect(posterWithToken('https://a/p.jpg', ''), 'https://a/p.jpg');
  });

  test('注入的 searchHandler 组装 DTO：聚合结果带 serverName 与带 token 海报', () async {
    final container = _container(servers: [_server('a', '服务器甲')]);
    final notifier = container.read(remoteSearchProvider.notifier);

    final items = await notifier.server.onSearch('影片');
    expect(items.single.id, 'a-1');
    expect(items.single.name, '服务器甲的影片');
    expect(items.single.serverId, 'a');
    expect(items.single.serverName, '服务器甲');
    expect(
      items.single.poster,
      'https://a.example.com/p.jpg?api_key=tok-a',
    );

    expect(await notifier.server.onSearch(''), isEmpty, reason: '空词直接空结果');
  });

  test('选片：写入 lastSelectedName 并广播 selections', () async {
    final container = await start();
    final notifier = container.read(remoteSearchProvider.notifier);
    // 预热名字缓存（经 onSearch 包装）
    await notifier.server.onSearch('影片');

    final events = <RemoteSelection>[];
    final sub = notifier.selections.listen(events.add);
    addTearDown(sub.cancel);

    final error = await notifier.server.onSelect('a', 'a-1');
    await Future<void>.delayed(Duration.zero);

    expect(error, isNull);
    expect(events.single.serverId, 'a');
    expect(events.single.itemId, 'a-1');
    expect(events.single.name, '服务器甲的影片');
    expect(container.read(remoteSearchProvider).lastSelectedName, '服务器甲的影片');
    await notifier.stop();
  });

  test('选片名字缓存未命中时回退 itemId', () async {
    final container = await start();
    final notifier = container.read(remoteSearchProvider.notifier);

    final error = await notifier.server.onSelect('a', 'unknown-id');
    await Future<void>.delayed(Duration.zero);

    expect(error, isNull);
    expect(container.read(remoteSearchProvider).lastSelectedName, 'unknown-id');
    await notifier.stop();
  });
}
