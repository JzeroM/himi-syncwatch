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

  group('GlobalSearchService.searchStream 增量流', () {
    test('慢服务器未回先发快服务器快照，终快照按服务器顺序合并', () async {
      final a = _config('a');
      final b = _config('b');
      final service = GlobalSearchService(serviceFactory: (server) {
        return _DelayedEmbyService(
          searchResults:
              server.id == 'a' ? [_item('a1', '甲影片')] : [_item('b1', '乙影片')],
          delay: server.id == 'a'
              ? const Duration(milliseconds: 150)
              : const Duration(milliseconds: 10),
        );
      });

      final emissions = await service.searchStream('影片', [a, b]).toList();

      expect(emissions, hasLength(2), reason: '先到先发 + 终快照');
      expect(emissions[0].single.item.id, 'b1', reason: '快的 b 先到');
      expect(emissions[1][0].item.id, 'a1', reason: '终快照按服务器顺序');
      expect(emissions[1][1].item.id, 'b1');
      expect(emissions[1][1].server.id, 'b');
    });

    test('中途空快照被抑制，避免未找到结果闪烁', () async {
      final a = _config('a');
      final b = _config('b');
      final service = GlobalSearchService(serviceFactory: (server) {
        return _DelayedEmbyService(
          searchResults: server.id == 'b' ? [_item('b1', '乙影片')] : const [],
          delay: server.id == 'b'
              ? const Duration(milliseconds: 30)
              : Duration.zero,
        );
      });

      final emissions = await service.searchStream('影片', [a, b]).toList();

      expect(emissions, hasLength(1), reason: 'a 的空快照不下发');
      expect(emissions.single.single.item.id, 'b1');
    });

    test('全部无结果时终份仍发一份空快照', () async {
      final a = _config('a');
      final b = _config('b');
      final service = GlobalSearchService(
        serviceFactory: (_) => FakeEmbyService(searchResults: const []),
      );

      final emissions = await service.searchStream('影片', [a, b]).toList();

      expect(emissions, [[]], reason: '空终份下发，UI 才能显示未找到结果');
    });

    test('单台异常留空不阻塞其余，终快照含成功台', () async {
      final bad = _config('bad');
      final good = _config('good');
      final service = GlobalSearchService(serviceFactory: (server) {
        if (server.id == 'bad') return _ThrowingEmbyService();
        return FakeEmbyService(searchResults: [_item('g1', '好片')]);
      });

      final emissions = await service.searchStream('片', [bad, good]).toList();

      expect(emissions, hasLength(1));
      expect(emissions.single.single.server.id, 'good');
    });

    test('空白查询与全部未认证发空终份，不触发工厂', () async {
      final built = <String>[];
      final guest = _config('guest', authenticated: false);
      final service = GlobalSearchService(serviceFactory: (server) {
        built.add(server.id);
        return FakeEmbyService();
      });

      expect(await service.searchStream('   ', [guest]).toList(), [[]]);
      expect(await service.searchStream('片', [guest]).toList(), [[]]);
      expect(built, isEmpty);
    });

    test('取消订阅后在途结果静默丢弃，不抛异常', () async {
      final a = _config('a');
      final service = GlobalSearchService(serviceFactory: (_) {
        return _DelayedEmbyService(
          searchResults: [_item('a1', '甲影片')],
          delay: const Duration(milliseconds: 30),
        );
      });

      final sub = service.searchStream('影片', [a]).listen((_) {});
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // 无异常即通过
    });
  });
}

class _ThrowingEmbyService extends FakeEmbyService {
  @override
  Future<List<MediaItem>> searchItems(String query) async {
    throw Exception('network down');
  }
}

class _DelayedEmbyService extends FakeEmbyService {
  _DelayedEmbyService({
    required super.searchResults,
    this.delay = Duration.zero,
  });

  final Duration delay;

  @override
  Future<List<MediaItem>> searchItems(String query) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return searchResults;
  }
}
