import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/dandanplay_client.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_match_memory.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_search_controller.dart';

class _FakeClient extends DandanplayClient {
  _FakeClient({this.result = const [], this.error})
      : super(baseUrl: 'http://fake.local');

  final List<MatchCandidate> result;
  final Object? error;

  @override
  Future<List<MatchCandidate>> searchEpisodes(String keyword) async {
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  late Directory tmp;
  late LocalDanmakuMatchMemory memory;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('danmaku_search_ctl');
    memory = LocalDanmakuMatchMemory(directory: tmp.path);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  DanmakuSearchController make({DandanplayClient? client}) =>
      DanmakuSearchController(
        client: client ??
            _FakeClient(result: const [
              MatchCandidate(
                episodeId: 101,
                animeTitle: '葬送的芙莉莲',
                episodeTitle: '第1集',
              ),
            ]),
        itemKey: DanmakuMatchKeys.item('http://s1', 'item-1'),
        nameKey: DanmakuMatchKeys.name('Title S01E01.mkv'),
        memory: memory,
      );

  group('load 与绑定状态', () {
    test('无记忆时 binding 为空、状态行「未匹配」', () async {
      final c = make();
      await c.load();
      expect(c.binding, isNull);
      expect(c.bindingLabel, '未匹配');
    });

    test('有记忆时 load 读出绑定', () async {
      await memory.put(
        itemKey: DanmakuMatchKeys.item('http://s1', 'item-1'),
        nameKey: DanmakuMatchKeys.name('Title S01E01.mkv'),
        record: const DanmakuMatchRecord(
          episodeId: 42,
          animeTitle: '某剧',
          episodeTitle: '第4集',
          source: DanmakuMatchSource.manual,
        ),
      );
      final c = make();
      await c.load();
      expect(c.binding?.episodeId, 42);
      expect(c.bindingLabel, '某剧 · 第4集（手动）');
    });
  });

  group('search', () {
    test('成功填充 results', () async {
      final c = make();
      await c.search('芙莉莲');
      expect(c.results, hasLength(1));
      expect(c.results.first.episodeId, 101);
      expect(c.searching, isFalse);
      expect(c.error, isNull);
    });

    test('空关键词提示', () async {
      final c = make();
      await c.search('   ');
      expect(c.error, '请输入搜索关键词');
      expect(c.results, isEmpty);
    });

    test('无结果提示', () async {
      final c = make(client: _FakeClient());
      await c.search('不存在');
      expect(c.results, isEmpty);
      expect(c.error, contains('未找到'));
    });

    test('异常转错误提示（不抛出）', () async {
      final c = make(client: _FakeClient(error: Exception('boom')));
      await c.search('x');
      expect(c.error, contains('弹幕搜索失败'));
      expect(c.results, isEmpty);
      expect(c.searching, isFalse);
    });
  });

  group('bind / unbind', () {
    test('bind 写 manual 记忆（两键同写）', () async {
      final c = make();
      await c.load();
      await c.bind(const MatchCandidate(
        episodeId: 101,
        animeTitle: '葬送的芙莉莲',
        episodeTitle: '第1集',
      ));
      expect(c.binding?.source, DanmakuMatchSource.manual);
      expect(c.bindingLabel, contains('手动'));
      final byName = await memory.get(
        nameKey: DanmakuMatchKeys.name('Title S01E01.mkv'),
      );
      expect(byName?.episodeId, 101);
      final byItem = await memory.get(
        itemKey: DanmakuMatchKeys.item('http://s1', 'item-1'),
      );
      expect(byItem?.source, DanmakuMatchSource.manual);
    });

    test('unbind 清记忆并复位状态', () async {
      final c = make();
      await c.bind(const MatchCandidate(episodeId: 7));
      await c.unbind();
      expect(c.binding, isNull);
      expect(c.bindingLabel, '未匹配');
      expect(
        await memory.get(itemKey: DanmakuMatchKeys.item('http://s1', 'item-1')),
        isNull,
      );
    });
  });

  test('revision 随状态变更递增（壳订阅依据）', () async {
    final c = make();
    final seen = <int>[];
    c.revision.addListener(() => seen.add(c.revision.value));
    await c.load();
    await c.search('芙莉莲');
    await c.bind(const MatchCandidate(episodeId: 101));
    await c.unbind();
    expect(seen.length, greaterThanOrEqualTo(4));
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThan(seen[i - 1]));
    }
    c.dispose();
  });
}
