import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/subtitle_style_store.dart';

void main() {
  late Directory dir;
  late SubtitleStyleStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('himi_style_store_');
    store = SubtitleStyleStore(directory: dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('SubtitleStylePrefs', () {
    test('默认值 = mdk 初始属性；isDefault', () {
      expect(SubtitleStylePrefs().isDefault, isTrue);
      expect(SubtitleStylePrefs(scale: 1.5).isDefault, isFalse);
      expect(SubtitleStylePrefs(delayMs: 100).isDefault, isFalse);
      expect(SubtitleStylePrefs().toJson(), {
        'scale': 1.0,
        'marginY': 22,
        'delayMs': 0,
      });
    });

    test('fromJson 缺字段回退默认；copyWith 局部更新', () {
      final p = SubtitleStylePrefs.fromJson(const {'scale': 2.0});
      expect(p.scale, 2.0);
      expect(p.marginY, 22);
      expect(p.delayMs, 0);
      expect(p.copyWith(marginY: 80),
          const SubtitleStylePrefs(scale: 2.0, marginY: 80));
      expect(
        p.copyWith(marginY: 80).scale,
        2.0,
        reason: 'copyWith 未传字段保留原值',
      );
    });
  });

  group('SubtitleStyleStore', () {
    test('put/get 往返恢复同内容样式', () async {
      expect(await store.get('item_a'), isNull);

      const prefs = SubtitleStylePrefs(scale: 1.5, marginY: 60, delayMs: -800);
      await store.put('item_a', prefs);
      expect(await store.get('item_a'), prefs);

      // 新实例（模拟重启后重进同内容）
      final reopened = SubtitleStyleStore(directory: dir.path);
      expect(await reopened.get('item_a'), prefs);
    });

    test('不同 itemId 互不干扰', () async {
      await store.put('a', const SubtitleStylePrefs(scale: 1.2));
      await store.put('b', const SubtitleStylePrefs(marginY: 100));
      expect((await store.get('a'))!.scale, 1.2);
      expect((await store.get('b'))!.marginY, 100);
    });

    test('文件损坏按无记录处理', () async {
      await File(
              '${dir.path}${Platform.pathSeparator}${SubtitleStyleStore.fileName}')
          .writeAsString('not-json{');
      expect(await store.load(), isEmpty);
      expect(await store.get('x'), isNull);
      // 仍可继续写入
      await store.put('x', const SubtitleStylePrefs());
      expect(await store.get('x'), const SubtitleStylePrefs());
    });

    test('超出容量按最旧淘汰（重插 = LRU 触达）', () async {
      for (var i = 0; i < SubtitleStyleStore.maxEntries + 5; i++) {
        await store.put('k$i', SubtitleStylePrefs(marginY: i));
      }
      var map = await store.load();
      expect(map.length, SubtitleStyleStore.maxEntries);
      expect(map.containsKey('k0'), isFalse, reason: '最旧条目被淘汰');
      expect(map.containsKey('k5'), isTrue, reason: '保留最近 100 条');
      expect(map.containsKey('k${SubtitleStyleStore.maxEntries + 4}'), isTrue);

      // 触达 k5（重插末尾）再插入新条目：被淘汰的应是次旧 k6 而非 k5
      await store.put('k5', const SubtitleStylePrefs(marginY: 5));
      await store.put('fresh', const SubtitleStylePrefs());
      map = await store.load();
      expect(map.length, SubtitleStyleStore.maxEntries);
      expect(map.containsKey('k5'), isTrue, reason: '触达后不被淘汰');
      expect(map.containsKey('k6'), isFalse, reason: '次旧条目被淘汰');
      expect(map.containsKey('k7'), isTrue);
    });

    test('写入文件为合法 JSON 结构', () async {
      await store.put('a', const SubtitleStylePrefs(scale: 1.5));
      final raw = await File(
              '${dir.path}${Platform.pathSeparator}${SubtitleStyleStore.fileName}')
          .readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['a'], {'scale': 1.5, 'marginY': 22, 'delayMs': 0});
    });
  });
}
