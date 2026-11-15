import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_match_memory.dart';

void main() {
  late Directory tmp;
  late LocalDanmakuMatchMemory memory;
  late DateTime now;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('danmaku_match_memory');
    now = DateTime(2026, 11, 15);
    memory = LocalDanmakuMatchMemory(directory: tmp.path, now: () => now);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  DanmakuMatchRecord rec({
    int episodeId = 101,
    String animeTitle = '葬送的芙莉莲',
    String episodeTitle = '第1集',
    DanmakuMatchSource source = DanmakuMatchSource.auto,
  }) =>
      DanmakuMatchRecord(
        episodeId: episodeId,
        animeTitle: animeTitle,
        episodeTitle: episodeTitle,
        source: source,
      );

  group('读写往返', () {
    test('put 后 itemKey / nameKey 均可命中', () async {
      await memory.put(
        itemKey: DanmakuMatchKeys.item('http://s1', 'item-1'),
        nameKey: DanmakuMatchKeys.name('Title S01E01.mkv'),
        record: rec(),
      );
      final byItem =
          await memory.get(itemKey: DanmakuMatchKeys.item('http://s1', 'item-1'));
      expect(byItem?.episodeId, 101);
      expect(byItem?.animeTitle, '葬送的芙莉莲');
      final byName =
          await memory.get(nameKey: DanmakuMatchKeys.name('Title S01E01.mkv'));
      expect(byName?.episodeId, 101);
    });

    test('itemKey 优先于 nameKey', () async {
      await memory.put(
        nameKey: DanmakuMatchKeys.name('a.mkv'),
        record: rec(episodeId: 1),
      );
      await memory.put(
        itemKey: DanmakuMatchKeys.item('http://s1', 'x'),
        nameKey: DanmakuMatchKeys.name('a.mkv'),
        record: rec(episodeId: 2),
      );
      final got = await memory.get(
        itemKey: DanmakuMatchKeys.item('http://s1', 'x'),
        nameKey: DanmakuMatchKeys.name('a.mkv'),
      );
      expect(got?.episodeId, 2);
    });

    test('未命中返回 null', () async {
      expect(await memory.get(itemKey: 'nope'), isNull);
    });
  });

  group('TTL 策略', () {
    test('auto 30 天过期', () async {
      await memory.put(
        itemKey: 'k',
        record: rec(source: DanmakuMatchSource.auto),
      );
      now = now.add(const Duration(days: 29));
      expect(await memory.get(itemKey: 'k'), isNotNull);
      now = now.add(const Duration(days: 2));
      expect(await memory.get(itemKey: 'k'), isNull);
    });

    test('manual 永不过期', () async {
      await memory.put(
        itemKey: 'k',
        record: rec(source: DanmakuMatchSource.manual),
      );
      now = now.add(const Duration(days: 3650));
      expect(await memory.get(itemKey: 'k'), isNotNull);
    });

    test('过期条目被清除（写入时顺带剪除）', () async {
      await memory.put(itemKey: 'old', record: rec());
      now = now.add(const Duration(days: 31));
      await memory.put(itemKey: 'new', record: rec(episodeId: 202));
      final file = File('${tmp.path}${Platform.pathSeparator}'
          '${LocalDanmakuMatchMemory.fileName}');
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final records = decoded['records'] as Map<String, dynamic>;
      expect(records.containsKey('old'), isFalse);
      expect(records.containsKey('new'), isTrue);
    });
  });

  group('LRU 与生命周期', () {
    test('超上限淘汰最旧', () async {
      for (var i = 0; i < LocalDanmakuMatchMemory.maxEntries + 5; i++) {
        await memory.put(itemKey: 'k$i', record: rec(episodeId: i));
      }
      expect(await memory.get(itemKey: 'k0'), isNull);
      expect(
        await memory.get(itemKey: 'k${LocalDanmakuMatchMemory.maxEntries + 4}'),
        isNotNull,
      );
    });

    test('remove 两键同删', () async {
      await memory.put(
        itemKey: 'i',
        nameKey: 'n',
        record: rec(),
      );
      await memory.remove(itemKey: 'i', nameKey: 'n');
      expect(await memory.get(itemKey: 'i'), isNull);
      expect(await memory.get(nameKey: 'n'), isNull);
    });

    test('clear 清空全部', () async {
      await memory.put(itemKey: 'a', record: rec());
      await memory.put(itemKey: 'b', record: rec());
      await memory.clear();
      expect(await memory.all(), isEmpty);
    });

    test('all() 按保存时间倒序', () async {
      await memory.put(itemKey: 'a', record: rec(episodeId: 1));
      now = now.add(const Duration(minutes: 1));
      await memory.put(itemKey: 'b', record: rec(episodeId: 2));
      final all = await memory.all();
      expect(all.map((e) => e.record.episodeId).toList(), [2, 1]);
    });
  });

  group('容错与键归一', () {
    test('损坏文件按空数据处理，不抛异常', () async {
      final file = File('${tmp.path}${Platform.pathSeparator}'
          '${LocalDanmakuMatchMemory.fileName}');
      await file.writeAsString('{ not json');
      expect(await memory.get(itemKey: 'k'), isNull);
      await memory.put(itemKey: 'k', record: rec());
      expect(await memory.get(itemKey: 'k'), isNotNull);
    });

    test('name 键归一：大小写/空白/扩展名', () {
      expect(
        DanmakuMatchKeys.name('  Title   S01E01.MKV '),
        DanmakuMatchKeys.name('title s01e01'),
      );
      expect(
        DanmakuMatchKeys.name('Title.mp4'),
        DanmakuMatchKeys.name('Title'),
      );
    });

    test('item 键区分服务器与条目', () {
      expect(
        DanmakuMatchKeys.item('http://s1', 'a'),
        isNot(DanmakuMatchKeys.item('http://s2', 'a')),
      );
    });
  });
}
