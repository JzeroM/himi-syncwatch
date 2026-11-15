import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/dandanplay_client.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_match_memory.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_search_controller.dart';

class _FakeClient extends DandanplayClient {
  _FakeClient({
    this.result = const [],
    this.error,
    this.matchResult = const [],
    this.byKeyword,
  }) : super(baseUrl: 'http://fake.local');

  final List<MatchCandidate> result;
  final Object? error;
  final List<MatchCandidate> matchResult;
  final Map<String, List<MatchCandidate>>? byKeyword;
  final List<String> queries = [];
  final List<String> episodeQueries = [];
  List<MatchCandidate> episodeResult = const [];

  @override
  Future<List<MatchCandidate>> searchEpisodes(
    String keyword, {
    int? episode,
  }) async {
    if (episode != null && episode > 0) {
      episodeQueries.add('$keyword→$episode');
      return episodeResult;
    }
    queries.add(keyword);
    if (error != null) throw error!;
    return byKeyword != null ? (byKeyword![keyword] ?? const []) : result;
  }

  @override
  Future<List<MatchCandidate>> match({
    required String fileName,
    int? fileSize,
  }) async {
    queries.add('match:$fileName');
    return matchResult;
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

  group('模糊搜索扩大范围（694）', () {
    test('多变体 + match 合并去重，早命中在前', () async {
      final client = _FakeClient(byKeyword: {
        '进击的巨人 第二季': const [
          MatchCandidate(episodeId: 1, animeTitle: '进击的巨人'),
          MatchCandidate(episodeId: 2, animeTitle: '进击的巨人'),
        ],
        '进击的巨人': const [
          MatchCandidate(episodeId: 2, animeTitle: '进击的巨人'),
          MatchCandidate(episodeId: 3, animeTitle: '进击的巨人'),
        ],
      }, matchResult: const [
        MatchCandidate(episodeId: 4, animeTitle: '进击的巨人'),
        MatchCandidate(episodeId: 1, animeTitle: '进击的巨人'),
      ]);
      final c = DanmakuSearchController(
        client: client,
        itemKey: 'i',
        nameKey: 'n',
        fileName: '[Subs] Shingeki no Kyojin S02E01.mkv',
        memory: memory,
      );
      await c.load();
      await c.search('进击的巨人 第二季');
      // 去重合并：1,2（首变体）→ 3（清洗变体）→ 4（match）
      expect(c.results.map((r) => r.episodeId).toList(), [1, 2, 3, 4]);
      expect(
        client.queries,
        contains('match:[Subs] Shingeki no Kyojin S02E01.mkv'),
      );
    });

    test('部分接口失败不致命（合并其余结果）', () async {
      final client = _FakeClient(result: const [
        MatchCandidate(episodeId: 9),
      ], matchResult: const []);
      final c = DanmakuSearchController(
        client: client,
        itemKey: 'i',
        nameKey: 'n',
        fileName: 'a.mkv',
        memory: memory,
      );
      await c.load();
      await c.search('葬送的芙莉莲');
      expect(c.results, isNotEmpty);
      expect(c.error, isNull);
    });
  });

  group('NeoPlayer 借鉴（694）', () {
    test('N1：带集号过滤查询置前（命中即本集排最前）', () async {
      final client = _FakeClient(result: const [
        MatchCandidate(episodeId: 101, animeTitle: '某剧'),
      ]);
      client.episodeResult = const [
        MatchCandidate(episodeId: 100, animeTitle: '某剧', episodeTitle: '第5集'),
      ];
      final c = DanmakuSearchController(
        client: client,
        itemKey: 'i',
        nameKey: 'n',
        episodeNumber: 5,
        memory: memory,
      );
      await c.load();
      await c.search('某剧');
      expect(client.episodeQueries.first, '某剧→5');
      // 过滤命中的 100 排最前
      expect(c.results.first.episodeId, 100);
    });

    test('N5：URL/协议前缀直接拦（不发请求）', () async {
      final client = _FakeClient(result: const []);
      final c = DanmakuSearchController(
        client: client,
        itemKey: 'i',
        nameKey: 'n',
        memory: memory,
      );
      await c.load();
      await c.search('https://example.com/x');
      expect(c.error, '搜索标题无效或属于协议前缀');
      expect(client.queries, isEmpty);
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
