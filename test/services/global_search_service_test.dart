import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/emby_server_config.dart';
import 'package:himi_syncwatch/models/media_item.dart';
import 'package:himi_syncwatch/services/global_search_service.dart';

import '../helpers/test_fakes.dart';

EmbyServerConfig _config(String id, {bool authenticated = true}) {
  return EmbyServerConfig(
    id: id,
    serverUrl: 'https://$id.example.com',
    serverName: '服务器$id',
    serverId: 'srv-$id',
    username: 'user',
    accessToken: authenticated ? 'token' : null,
    userId: authenticated ? 'uid' : null,
  );
}

MediaItem _item(String id, String name) =>
    MediaItem(id: id, name: name, type: 'Movie');

void main() {
  group('GlobalSearchService', () {
    test('并发搜索多服务器，结果按服务器顺序拼接', () async {
      final a = _config('a');
      final b = _config('b');
      final service = GlobalSearchService(serviceFactory: (server) {
        return FakeEmbyService(
          searchResults: server.id == 'a'
              ? [_item('a1', '甲影片'), _item('a2', '乙影片')]
              : [_item('b1', '丙影片')],
        );
      });

      final results = await service.search('影片', [a, b]);

      expect(results, hasLength(3));
      expect(results[0].item.id, 'a1');
      expect(results[0].server.id, 'a');
      expect(results[1].item.id, 'a2');
      expect(results[2].item.id, 'b1');
      expect(results[2].server.id, 'b');
    });

    test('未认证服务器被跳过，不触发服务工厂', () async {
      final ok = _config('ok');
      final guest = _config('guest', authenticated: false);
      final built = <String>[];
      final service = GlobalSearchService(serviceFactory: (server) {
        built.add(server.id);
        return FakeEmbyService(searchResults: [_item('x1', '影片')]);
      });

      final results = await service.search('影片', [ok, guest]);

      expect(built, ['ok']);
      expect(results, hasLength(1));
      expect(results.single.server.id, 'ok');
    });

    test('单台服务器异常不阻塞其余服务器', () async {
      final bad = _config('bad');
      final good = _config('good');
      final service = GlobalSearchService(serviceFactory: (server) {
        if (server.id == 'bad') {
          return _ThrowingEmbyService();
        }
        return FakeEmbyService(searchResults: [_item('g1', '好片')]);
      });

      final results = await service.search('片', [bad, good]);

      expect(results, hasLength(1));
      expect(results.single.server.id, 'good');
    });

    test('空白查询直接返回空且不触发工厂', () async {
      final a = _config('a');
      final built = <String>[];
      final service = GlobalSearchService(serviceFactory: (server) {
        built.add(server.id);
        return FakeEmbyService();
      });

      expect(await service.search('   ', [a]), isEmpty);
      expect(built, isEmpty);
    });

    test('全部未认证返回空', () async {
      final guest = _config('guest', authenticated: false);
      final service = GlobalSearchService(
        serviceFactory: (_) => FakeEmbyService(
          searchResults: [_item('x', '不应出现')],
        ),
      );

      expect(await service.search('片', [guest]), isEmpty);
    });
  });
}

class _ThrowingEmbyService extends FakeEmbyService {
  @override
  Future<List<MediaItem>> searchItems(String query) async {
    throw Exception('network down');
  }
}
