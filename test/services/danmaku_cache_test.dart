import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/danmaku/danmaku_cache.dart';

void main() {
  group('DanmakuCache', () {
    test('put/get 基本读写，miss 返回 null', () {
      final cache = DanmakuCache<int>();
      expect(cache.get('a'), isNull);
      cache.put('a', 1);
      expect(cache.get('a'), 1);
    });

    test('TTL 过期后返回 null 并移除', () {
      var now = DateTime(2026, 1, 1, 12);
      final cache = DanmakuCache<String>(
        ttl: const Duration(hours: 6),
        now: () => now,
      );
      cache.put('k', 'v');
      now = now.add(const Duration(hours: 5));
      expect(cache.get('k'), 'v', reason: '5h < 6h 仍有效');
      now = now.add(const Duration(hours: 1, seconds: 1));
      expect(cache.get('k'), isNull, reason: '超 6h 过期');
      expect(cache.length, 0, reason: '过期项读取时被清除');
    });

    test('同 key 覆盖写不占双份容量', () {
      final cache = DanmakuCache<int>(maxEntries: 3);
      cache.put('a', 1);
      cache.put('a', 2);
      expect(cache.length, 1);
      expect(cache.get('a'), 2);
    });

    test('超容量按插入序淘汰最旧', () {
      final cache = DanmakuCache<int>(maxEntries: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      cache.put('d', 4);
      expect(cache.length, 3);
      expect(cache.get('a'), isNull, reason: '最旧被淘汰');
      expect(cache.get('d'), 4);
    });

    test('clear 清空', () {
      final cache = DanmakuCache<int>();
      cache.put('a', 1);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.get('a'), isNull);
    });
  });
}
