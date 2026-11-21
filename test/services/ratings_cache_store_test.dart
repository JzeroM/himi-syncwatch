import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/models/hero_rating.dart';
import 'package:himi_syncwatch/services/ratings_cache_store.dart';

/// 假安全存储（内存字典）：只实现 read/write，其余成员兜底 noSuchMethod。
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String?> data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    data[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('RatingsCacheEntry 序列化', () {
    test('往返保留徽章/时间/hasData', () {
      final entry = RatingsCacheEntry(
        badges: const [
          HeroRatingBadge(RatingPlatform.imdb, '7.6'),
          HeroRatingBadge(RatingPlatform.douban, '9.4'),
        ],
        at: DateTime.fromMillisecondsSinceEpoch(1795250000000),
        hasData: true,
      );
      final round = RatingsCacheEntry.fromJson(entry.toJson())!;
      expect(round.badges, entry.badges);
      expect(round.at, entry.at);
      expect(round.hasData, isTrue);
    });

    test('未知平台行容错跳过；脏 JSON → null', () {
      final entry = RatingsCacheEntry.fromJson({
        'at': 1795250000000,
        'hasData': false,
        'badges': [
          ['noSuchPlatform', '1.0'],
          ['imdb', '7.6'],
        ],
      })!;
      expect(entry.badges, [const HeroRatingBadge(RatingPlatform.imdb, '7.6')]);
      expect(RatingsCacheEntry.fromJson({'at': 'x'}), isNull);
      expect(RatingsCacheEntry.fromJson('junk'), isNull);
    });
  });

  group('MemoryRatingsCacheStore', () {
    test('读写往返', () async {
      final store = MemoryRatingsCacheStore();
      final entry = RatingsCacheEntry(
        badges: const [HeroRatingBadge(RatingPlatform.imdb, '7.6')],
        at: DateTime.now(),
        hasData: true,
      );
      await store.write('omdb:imdb:tt1', entry);
      expect((await store.read('omdb:imdb:tt1'))!.badges, entry.badges);
      expect(await store.read('missing'), isNull);
    });
  });

  group('SecureRatingsCacheStore（698 N7-I 持久层）', () {
    test('写后新实例可读（跨启动语义：同底层存储）', () async {
      final storage = _FakeSecureStorage();
      final store1 = SecureRatingsCacheStore(storage: storage);
      final entry = RatingsCacheEntry(
        badges: const [HeroRatingBadge(RatingPlatform.douban, '9.4')],
        at: DateTime.now(),
        hasData: true,
      );
      await store1.write('douban:douban:1', entry);

      final store2 = SecureRatingsCacheStore(storage: storage);
      final read = await store2.read('douban:douban:1');
      expect(read!.badges, entry.badges);
      expect(read.hasData, isTrue);
    });

    test('超容淘汰最旧', () async {
      final storage = _FakeSecureStorage();
      final store = SecureRatingsCacheStore(storage: storage, maxEntries: 2);
      RatingsCacheEntry entry(int ageDays) => RatingsCacheEntry(
            badges: const [],
            at: DateTime.now().subtract(Duration(days: ageDays)),
            hasData: true,
          );
      await store.write('a', entry(3));
      await store.write('b', entry(2));
      await store.write('c', entry(1)); // 超容 → 淘汰最旧 a
      expect(await store.read('a'), isNull);
      expect(await store.read('b'), isNotNull);
      expect(await store.read('c'), isNotNull);
    });

    test('底层脏 JSON → 当空缓存处理（不抛）', () async {
      final storage = _FakeSecureStorage()..data['himi_ratings_cache'] = '{{{';
      final store = SecureRatingsCacheStore(storage: storage);
      expect(await store.read('x'), isNull);
      // 仍可正常写入。
      await store.write('x', RatingsCacheEntry(
        badges: const [],
        at: DateTime.now(),
        hasData: false,
      ));
      expect(await store.read('x'), isNotNull);
    });
  });
}
